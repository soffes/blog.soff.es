require 'date'
require 'redcarpet'
require 'json'
require 'nokogiri'
require 'aws-sdk-s3'
require 'dimensions'
require 'safe_yaml'
require 'soffes/blog/markdown_renderer'
require 'soffes/blog/redis'
require 'soffes/blog/posts_controller'

module Soffes
  module Blog
    class Importer
      BLOG_GIT_URL = 'https://github.com/soffes/blog.git'.freeze
      MARKDOWN_OPTIONS = options = {
        no_intra_emphasis: true,
        tables: true,
        fenced_code_blocks: true,
        autolink: true,
        strikethrough: true,
        space_after_headers: true,
        superscript: true,
        with_toc_data: true,
        underline: true,
        highlight: true
      }.freeze
      AWS_ACCESS_KEY_ID = ENV['AWS_ACCESS_KEY_ID']
      AWS_SECRET_ACCESS_KEY = ENV['AWS_SECRET_ACCESS_KEY']
      AWS_S3_REGION = ENV['AWS_S3_REGION'] || 'us-east-1'

      def initialize(local_posts_path: 'tmp/repo', update_posts: true, include_drafts: false, bucket_name: ENV['AWS_S3_BUCKET_NAME'], use_s3: true)
        @local_posts_path = local_posts_path
        @update_posts = update_posts
        @bucket_name = bucket_name
        @include_drafts = include_drafts
        @use_s3 = use_s3
      end

      def import
        if @update_posts
          if !File.exists?(@local_posts_path)
            puts 'Cloning posts...'
            `git clone --depth 1 #{BLOG_GIT_URL} #{@local_posts_path}`
          else
            puts 'Updating posts...'
            `cd #{@local_posts_path} && git pull origin master`
          end
        else
          raise 'Posts not found.' unless File.exists?(@local_posts_path)
        end

        markdown = Redcarpet::Markdown.new(Soffes::Blog::MarkdownRenderer, MARKDOWN_OPTIONS)
        count = 0

        # Posts
        paths = if @include_drafts
          Dir["#{@local_posts_path}/drafts/*"]
        else
          Dir["#{@local_posts_path}/published/*"]
        end

        paths.each do |path|
          matches = path.match(/\/(\d{4})-(\d{2})-(\d{2})-([\w\-]+)$/)
          key = matches[4]

          puts "Importing #{key}"

          # Load content
          contents = File.open("#{path}/#{key}.markdown").read

          # Meta data
          meta = {
            'key' => key,
            'title' => key.capitalize,
            'published_at' => Date.new(matches[1].to_i, matches[2].to_i, matches[3].to_i).to_time.utc.to_i
          }

          # Extract YAML front matter
          if result = contents.match(/\A(---\s*\n.*?\n?)^(---\s*$\n?)/m)
            contents = contents[(result[0].length)...(contents.length)]
            meta.merge!(YAML.safe_load(result[0]))
          end

          # Upload cover image
          if @use_s3 && (cover_image = meta['cover_image'])
            local_path = "#{path}/#{cover_image}"
            meta['cover_image'] = upload(local_path, "#{key}/#{cover_image}")

            dimensions = Dimensions.dimensions local_path
            meta['cover_image_width'] = dimensions.first
            meta['cover_image_height'] = dimensions.last
          end

          # Parse Markdown
          html = markdown.render(contents)

          # Remove H1
          doc = Nokogiri::HTML.fragment(html)
          h1 = doc.search('.//h1').remove
          meta['title'] = h1.text if h1.text.length > 0

          # Upload images
          doc.css('img').each do |i|
            src = i['src']
            next if src.start_with?('http')

            image_path = "#{path}/#{src}"
            next unless File.exists?(image_path)

            i['src'] = upload(image_path, "#{key}/#{src}")
          end

          # Add HTML
          meta['html'] = doc.to_html.strip

          # Add naïve word count
          meta['word_count'] = doc.text.split(/\s+/m).length

          # Add excerpt
          nodes = []
          doc.children.each do |block|
            next if block.to_html.strip.empty?
            next if block.name == 'h2' || block.name == 'h3'
            nodes << block
            break if nodes.count == 3
          end
          meta['excerpt_html'] = nodes.map { |e| e.to_html }.join
          meta['excerpt_text'] = nodes.map { |e| e.text }.join(' ')

          # Persist!
          PostsController.insert_post(meta)
          count += 1
        end

        puts 'Done!'
        count
      end

      private

      def redis
        Soffes::Blog.redis
      end

      def aws
        @aws ||= Aws::S3::Client.new(
          region: AWS_S3_REGION,
          access_key_id: AWS_ACCESS_KEY_ID,
          secret_access_key: AWS_SECRET_ACCESS_KEY
        )
      end

      def upload(local, key)
        if @use_s3 && !redis.sismember('uploaded', key)
          puts "  Uploading #{key}"
          bucket = Aws::S3::Resource.new(client: aws).bucket(@bucket_name)
          bucket.object(key).upload_file(local, acl: 'public-read')
          redis.sadd('uploaded', key)
        end

        "https://#{@bucket_name}.s3.amazonaws.com/#{key}"
      end
    end
  end
end
