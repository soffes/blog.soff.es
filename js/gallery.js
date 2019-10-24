class Lightbox {
  // Close the lightbox
  close() {
    if (!window.lightbox) {
      return;
    }

    window.lightbox.parentNode.removeChild(window.lightbox);
    window.lightbox = null;
  }

  // Create the elements if needed
  setup() {
    if (window.lightbox) {
      return;
    }

    const lightbox = document.createElement('DIV');
    lightbox.className = 'lightbox';
    lightbox.setAttribute('tabindex', '-1');

    document.body.appendChild(lightbox);
    window.lightbox = lightbox;

    lightbox.addEventListener('keydown', (event) => {
      // Escape
      if (event.keyCode === 27) {
        this.close();
        event.preventDefault();
        return;
      }
    });

    lightbox.addEventListener('click', () => {
      this.close();
    });
  }

  // Show an image. This expects an `<img>` as its parameter.
  show(element) {
    if (!element) {
      return;
    }

    this.setup();

    // Reset
    window.lightbox.innerHTML = '';

    const image = element.cloneNode(true);
    image.removeAttribute('style');
    window.lightbox.appendChild(image);
  }
}


class PhotoGallery extends HTMLElement {
  connectedCallback() {
    for (let image of this._allImages()) {
      image.addEventListener('click', (event) => {
        event.preventDefault();
        new Lightbox().show(image);
      });
    }
  }

  _allImages() {
    return Array.from(this.querySelectorAll('img'));
  }
}
window.customElements.define('photo-gallery', PhotoGallery);


const rowTemplate = document.createElement('template');
rowTemplate.innerHTML = `
<style>
:host {
  display: grid;
  width: 100%;
  grid-gap: 8px;
  margin-bottom: 8px;
}

img {
  width: 100%;
}

[style*="--aspect-ratio"] > :first-child {
  width: 100%;
}

[style*="--aspect-ratio"] > img {
  height: auto;
}

@supports (--custom:property) {
  [style*="--aspect-ratio"] {
    position: relative;
  }

  [style*="--aspect-ratio"]::before {
    content: "";
    display: block;
    padding-bottom: calc(100% / (var(--aspect-ratio)));
  }

  [style*="--aspect-ratio"] > :first-child {
    position: absolute;
    top: 0;
    left: 0;
    height: 100%;
  }
}
</style>`;
class PhotoGalleryRow extends HTMLElement {
  constructor() {
    super();

    this.attachShadow({ mode: "open" });
    this.shadowRoot.appendChild(rowTemplate.content.cloneNode(true));
  }

  connectedCallback() {
    const images = this.querySelectorAll("img");
    let columns = "";
    for (let image of images) {
      image.parentNode.removeChild(image);

      const wrapper = document.createElement("div");
      wrapper.style = "--aspect-ratio:" + image.getAttribute("data-width") + "/" + image.getAttribute("data-height")
      wrapper.appendChild(image);
      this.shadowRoot.appendChild(wrapper);
      columns += "1fr ";
    }

    this.style.gridTemplateColumns = columns.trim();
  }
}
window.customElements.define('photo-gallery-row', PhotoGalleryRow);
