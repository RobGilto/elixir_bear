// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/elixir_bear"
import topbar from "../vendor/topbar"

// Custom hooks
const Hooks = {
  PasteUpload: {
    mounted() {
      this.el.addEventListener("paste", (e) => {
        const items = e.clipboardData?.items
        if (!items) return

        for (let i = 0; i < items.length; i++) {
          if (items[i].type.indexOf("image") !== -1) {
            e.preventDefault()
            const blob = items[i].getAsFile()
            const file = new File([blob], `pasted-image-${Date.now()}.png`, { type: blob.type })

            // Get the file input element from the upload
            const uploadInput = this.el.querySelector('input[type="file"]')
            if (uploadInput) {
              // Create a new FileList-like object
              const dataTransfer = new DataTransfer()
              // Add existing files
              if (uploadInput.files) {
                for (let f of uploadInput.files) {
                  dataTransfer.items.add(f)
                }
              }
              // Add the pasted file
              dataTransfer.items.add(file)
              // Set the files on the input
              uploadInput.files = dataTransfer.files
              // Trigger change event to notify LiveView
              uploadInput.dispatchEvent(new Event('change', { bubbles: true }))
            }
            break
          }
        }
      })
    }
  },
  CodeBlock: {
    mounted() {
      this.setupCodeBlockButtons()
    },
    updated() {
      this.setupCodeBlockButtons()
    },
    setupCodeBlockButtons() {
      // Setup reveal/hide buttons
      this.el.querySelectorAll('.reveal-button').forEach(button => {
        button.onclick = (e) => {
          e.preventDefault()
          const pre = button.closest('pre')
          const code = pre.querySelector('code')

          if (code.classList.contains('revealed')) {
            code.classList.remove('revealed')
            button.textContent = 'Reveal'
            button.classList.remove('revealed')
          } else {
            code.classList.add('revealed')
            button.textContent = 'Hide'
            button.classList.add('revealed')
          }
        }
      })

      // Setup edit buttons
      this.el.querySelectorAll('.edit-button').forEach(button => {
        button.onclick = (e) => {
          e.preventDefault()
          const pre = button.closest('pre')
          const code = pre.querySelector('code')
          const textarea = pre.querySelector('.code-editor')
          const messageId = pre.getAttribute('data-message-id')

          if (button.classList.contains('editing')) {
            // Save mode - send to server for persistence
            const newCode = textarea.value

            if (messageId) {
              // Push event to LiveView to save in database
              this.pushEvent("update_code_block", {
                message_id: parseInt(messageId),
                new_content: newCode
              })

              // Show saving feedback
              button.textContent = 'Saving...'
              button.disabled = true
            } else {
              // No message ID - just update locally (backward compatibility)
              this.updateCodeBlockLocally(code, textarea, button, newCode)
            }
          } else {
            // Edit mode - show textarea
            code.classList.add('editing')
            textarea.classList.add('active')
            button.textContent = 'Save'
            button.classList.add('editing')

            // Focus the textarea
            textarea.focus()
          }
        }
      })

      // Setup copy buttons
      this.el.querySelectorAll('.copy-button').forEach(button => {
        button.onclick = (e) => {
          e.preventDefault()
          const code = button.getAttribute('data-clipboard-text')
          navigator.clipboard.writeText(code).then(() => {
            const originalText = button.textContent
            button.textContent = 'Copied!'
            button.classList.add('copied')
            setTimeout(() => {
              button.textContent = originalText
              button.classList.remove('copied')
            }, 2000)
          }).catch(err => {
            console.error('Failed to copy:', err)
          })
        }
      })
    },
    updateCodeBlockLocally(code, textarea, button, newCode) {
      // Local update without database persistence
      code.textContent = newCode

      // Update the copy button's data
      const copyButton = button.closest('pre').querySelector('.copy-button')
      if (copyButton) {
        const escapedCode = newCode
          .replace(/&/g, '&amp;')
          .replace(/"/g, '&quot;')
          .replace(/</g, '&lt;')
          .replace(/>/g, '&gt;')
        copyButton.setAttribute('data-clipboard-text', escapedCode)
      }

      // Switch back to view mode
      code.classList.remove('editing')
      textarea.classList.remove('active')
      button.textContent = 'Edit'
      button.classList.remove('editing')

      // Show success feedback
      button.textContent = 'Saved!'
      button.classList.add('success')
      setTimeout(() => {
        button.textContent = 'Edit'
        button.classList.remove('success')
      }, 2000)
    }
  }
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, ...Hooks},
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

