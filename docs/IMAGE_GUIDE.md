# Image Guide for ElixirBear README

This guide lists all the images referenced in the README and provides specifications for creating them.

## Directory Structure

```
elixir_bear/
└── docs/
    └── images/
        ├── chat-interface.png
        ├── multimodal-example.png
        ├── solutions-library.png
        ├── settings.png
        ├── architecture.png
        ├── demo.gif
        └── tech-stack.png
```

## Image Specifications

### 1. `chat-interface.png`
**Purpose:** Main hero image showing the chat interface in action

**What to capture:**
- Full browser window or cropped application view
- Active conversation with at least 3-4 message exchanges
- Show code blocks with syntax highlighting
- Visible file attachments (icons/thumbnails)
- Clean, professional UI

**Recommended size:** 1200x800px or larger
**Format:** PNG
**Tips:** Take screenshot during an interesting coding conversation

---

### 2. `multimodal-example.png`
**Purpose:** Demonstrate multi-modal capabilities (image + AI analysis)

**What to capture:**
- A message with an image attachment visible
- AI's response analyzing/describing the image
- Shows the power of image understanding

**Recommended size:** 1200x700px
**Format:** PNG
**Tips:** Upload a diagram, screenshot, or chart and ask AI to analyze it

---

### 3. `solutions-library.png`
**Purpose:** Showcase the solutions management feature

**What to capture:**
- Solutions list/grid view
- Multiple solutions with visible tags
- Code snippets with syntax highlighting
- Well-organized, populated library

**Recommended size:** 1200x800px
**Format:** PNG
**Tips:** Create 5-10 sample solutions with varied tags before capturing

---

### 4. `settings.png`
**Purpose:** Show the configuration interface

**What to capture:**
- Settings page with form fields
- API key configuration section
- Feature toggles (solution extraction, router)
- Clean, professional form layout

**Recommended size:** 1000x700px
**Format:** PNG
**Tips:** You can blur out actual API keys for security

---

### 5. `architecture.png`
**Purpose:** Simple technical architecture diagram

**What to create:**
- Flow diagram showing: User → LiveView → AI Provider → Background Worker → Database
- Use boxes and arrows
- Include icons if possible (optional)
- Keep it simple and clean

**Recommended size:** 1000x400px or 1200x500px
**Format:** PNG
**Tools:** draw.io, Excalidraw, Figma, or even PowerPoint/Google Slides
**Style:** Clean, minimal, professional

Example flow:
```
[User Browser] ←WebSocket→ [Phoenix LiveView]
                                   ↓
                          [OpenAI/Ollama API]
                                   ↓
                          [Background Worker]
                                   ↓
                             [SQLite DB]
```

---

### 6. `demo.gif`
**Purpose:** Animated walkthrough of key features

**What to show (in sequence):**
1. Start on home page
2. Create new conversation
3. Type and send a coding question
4. Show streaming response with code blocks
5. (Optional) Navigate to Solutions page showing extracted solution
6. (Optional) Start new chat and show router suggesting the solution

**Recommended size:** 1000x600px to 1200x700px
**Format:** GIF
**Duration:** 15-30 seconds
**Tools:**
- macOS: QuickTime + Gifski
- Linux: Peek, SimpleScreenRecorder + ffmpeg
- Windows: ScreenToGif
- Cross-platform: OBS Studio + online GIF converter

**Tips:**
- Keep it smooth (at least 15 fps)
- Not too fast - viewers need to follow along
- Optimize file size (aim for under 10MB)

---

### 7. `tech-stack.png`
**Purpose:** Visual banner showing all technologies used

**What to create:**
- Horizontal banner with technology logos
- Include: Elixir, Phoenix, LiveView, OpenAI, Ollama
- Professional, aligned layout
- Optional: Add technology names under logos

**Recommended size:** 1000x200px or 1200x250px
**Format:** PNG
**Tools:** Figma, Canva, PowerPoint, or image editor
**Resources for logos:**
- [Elixir Logo](https://github.com/elixir-lang/elixir-lang.github.com/tree/main/images/logo)
- [Phoenix Logo](https://github.com/phoenixframework/phoenix/tree/master/priv/static/phoenix.png)
- [OpenAI Brand](https://openai.com/brand)
- Search for "Ollama logo" or use llama emoji

**Tips:** Use transparent backgrounds, maintain consistent logo sizes

---

## Quick Capture Checklist

Before taking screenshots:
- [ ] Set browser to reasonable zoom level (100% or 110%)
- [ ] Use a consistent browser window size
- [ ] Clean up any sensitive information
- [ ] Ensure good contrast and readability
- [ ] Have sample data ready (conversations, solutions)

For best results:
- Take screenshots in good lighting
- Use the application's actual interface (not mockups)
- Ensure text is crisp and readable
- Keep consistent styling across all images

## Optional Enhancements

Consider adding these optional images later:
- `landing-page.png` - If you create a landing page
- `mobile-view.png` - If you add mobile responsiveness
- `dark-mode.png` - If you implement dark theme
- `solution-router-example.png` - Show the router in action with suggestions

---

**Note:** All images should be committed to the repository. GitHub will render them automatically in the README when viewing on GitHub.com.
