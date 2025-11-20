# ElixirBear 🐻✨

> A production-ready AI chat platform built with Phoenix LiveView, featuring intelligent solution management, multi-modal conversations, and real-time streaming.

[![Elixir](https://img.shields.io/badge/Elixir-1.15+-4B275F.svg)](https://elixir-lang.org/)
[![Phoenix](https://img.shields.io/badge/Phoenix-1.8-orange.svg)](https://phoenixframework.org/)
[![LiveView](https://img.shields.io/badge/LiveView-1.1-blue.svg)](https://hexdocs.pm/phoenix_live_view)
[![License](https://img.shields.io/badge/License-Personal-green.svg)](LICENSE)

**ElixirBear** is a sophisticated AI chat application that goes beyond simple conversations. It intelligently extracts, organizes, and retrieves code solutions from your chat history, making it a powerful tool for developers who want to build a personal knowledge base while interacting with AI models.

---

![Main Chat Interface](/docs/images/chat-interface.png)


## ✨ Key Features

### 💬 Intelligent Chat Interface
Transform your AI conversations into a powerful development tool:

- **🤖 Dual AI Provider Support**: Seamlessly switch between OpenAI's GPT models and local Ollama models
- **🖼️ Multi-Modal Conversations**: Attach images, audio files, and code files directly to your messages
- **⚡ Real-Time Streaming**: Experience instant, token-by-token response streaming powered by Phoenix LiveView
- **📁 Smart Conversation Management**: Organize multiple conversation threads with easy navigation and search
- **🎨 Customizable Interface**: Personalize your workspace with custom background images and themes

![Multi-modal Chat](/docs/images/multimodal-example.png)


### 🧠 AI-Powered Solution Management
The standout feature that sets ElixirBear apart:

- **🔍 Automatic Solution Extraction**: Let AI identify and extract valuable code solutions from your conversations automatically
- **🏷️ Smart Tagging System**: Organize solutions with custom tags for lightning-fast retrieval
- **🎯 Intelligent Solution Router**: AI-powered matching system that suggests relevant solutions as you chat
- **📚 Code Block Support**: Store multiple code blocks per solution with full syntax highlighting
- **🔄 Reusability at Scale**: Build your personal library of battle-tested solutions

![Solutions Library](/docs/images/solutions-library.png)

### 📎 Comprehensive File Support
Work with virtually any file type in your conversations:

| Category | Supported Formats |
|----------|-------------------|
| **Images** | `.jpg`, `.jpeg`, `.png`, `.gif`, `.webp` |
| **Audio** | `.mp3`, `.mpga`, `.m4a`, `.wav` |
| **Elixir** | `.ex`, `.exs`, `.heex`, `.eex`, `.leex` |
| **Web** | `.js`, `.jsx`, `.ts`, `.tsx`, `.css`, `.scss`, `.html` |
| **Config** | `.json`, `.xml`, `.yaml`, `.yml`, `.toml` |
| **Languages** | `.py`, `.rb`, `.java`, `.go`, `.rs`, `.c`, `.cpp`, `.sh` and more |
| **Documentation** | `.txt`, `.md` |

### 🎯 Technical Highlights

**Real-time Architecture**
- Built on Phoenix PubSub for instant message delivery
- LiveView integration eliminates the need for separate frontend framework
- WebSocket-based streaming for token-by-token AI responses

**Smart Background Processing**
- Asynchronous conversation processing with dedicated workers
- Non-blocking solution extraction and routing
- Efficient handling of file uploads and processing

**Developer-Friendly Design**
- Clean separation of concerns with domain-driven design
- Comprehensive test coverage
- Pre-commit hooks for code quality
- SQLite for simple deployment and portability


## Technology Stack

- **Backend**: Elixir 1.15+ with Phoenix Framework 1.8
- **Frontend**: Phoenix LiveView 1.1 with TailwindCSS
- **Database**: SQLite (via Ecto SQLite3)
- **AI Integration**: OpenAI API & Ollama support
- **Real-time**: Phoenix PubSub for live updates
- **Assets**: esbuild & Tailwind CSS

## Prerequisites

- Elixir 1.15 or later
- Erlang/OTP 24 or later
- Node.js (for asset compilation)
- SQLite3

## Installation

1. Clone the repository:
```bash
git clone https://github.com/RobGilto/elixir_bear.git
cd elixir_bear
```

2. Install dependencies and set up the database:
```bash
mix setup
```

This will:
- Install Elixir dependencies
- Create and migrate the database
- Install and build assets

3. Configure your AI provider settings:
   - For OpenAI: Set your API key in the Settings page after starting the server
   - For Ollama: Ensure Ollama is running locally and configure the endpoint in Settings

## 🚀 Quick Start

Start the Phoenix server:

```bash
mix phx.server
```

Or start it inside IEx for interactive debugging:

```bash
iex -S mix phx.server
```

Visit [`localhost:4000`](http://localhost:4000) in your browser.

### ⚙️ First-time Setup

1. **Configure AI Provider** - Navigate to Settings (`/settings`):
   - Add your OpenAI API key for GPT models, or
   - Configure Ollama endpoint for local models (e.g., `http://localhost:11434`)

2. **Enable Smart Features** (Optional):
   - Enable automatic solution extraction
   - Configure the solution router for AI-powered suggestions

3. **Start Chatting** - Create a new conversation and start building your knowledge base!


## 🎬 Demo

1. *Starting a new conversation*
2. *Asking a coding question*
3. *Getting a solution with code blocks*
4. *Solution being automatically extracted and tagged*
5. *Later query showing the solution being suggested by the router*

## Development

### Running Tests

```bash
mix test
```

### Code Formatting

```bash
mix format
```

### Pre-commit Checks

Before committing your changes, run:

```bash
mix precommit
```

This will:
- Compile with warnings as errors
- Remove unused dependencies
- Format code
- Run the test suite

### Database Operations

Reset the database:
```bash
mix ecto.reset
```

Run migrations:
```bash
mix ecto.migrate
```

## 📁 Project Structure

The codebase follows Phoenix conventions with domain-driven design:

```
lib/
├── elixir_bear/               # 🧠 Core business logic
│   ├── chat/                  # 💬 Chat domain
│   │   ├── conversation.ex   # Conversation schema and queries
│   │   ├── message.ex        # Message schema
│   │   └── settings.ex       # Application settings
│   ├── solutions/             # 🔍 Solutions domain
│   │   ├── solution.ex       # Solution schema and queries
│   │   ├── tag.ex            # Tag system
│   │   ├── extractor.ex      # AI-powered solution extraction
│   │   └── router.ex         # Smart solution matching
│   ├── ollama.ex             # 🦙 Ollama API client
│   ├── openai.ex             # 🤖 OpenAI API client
│   └── conversation_worker.ex # ⚙️ Background processing
│
├── elixir_bear_web/          # 🌐 Web interface
│   ├── live/                 # ⚡ LiveView modules
│   │   ├── chat_live.ex     # Main chat interface
│   │   ├── solutions_live.ex # Solutions library
│   │   └── settings_live.ex  # Settings management
│   ├── components/           # 🧩 Reusable UI components
│   └── router.ex            # 🛣️ Application routes
│
├── test/                     # 🧪 Comprehensive test suite
└── priv/                     # 📦 Static assets & migrations
```

## 🏗️ Architecture Decisions

**Why Phoenix LiveView?**
- Real-time updates without complex JavaScript frameworks
- Server-side rendering with minimal client-side code
- Built-in WebSocket handling and connection management
- Simplified state management

**Why SQLite?**
- Zero-configuration database setup
- Perfect for single-user or small-team deployments
- Easy backup and portability
- Excellent performance for this use case

**Why Background Workers?**
- Non-blocking AI API calls
- Smooth user experience during solution extraction
- Scalable processing for multiple concurrent conversations

## Configuration

Key configuration files:
- `config/config.exs` - Application configuration
- `config/dev.exs` - Development environment settings
- `config/prod.exs` - Production environment settings
- `AGENTS.md` - Development guidelines and coding standards

## 🎯 Use Cases

**For Developers**
- Build a personal library of coding solutions and patterns
- Quickly reference solutions from past AI conversations
- Learn by reviewing and organizing code snippets

**For Teams**
- Share and reuse common solutions across projects
- Document tribal knowledge in an accessible format
- Onboard new team members with curated solutions

**For Learners**
- Study AI-generated solutions with syntax highlighting
- Organize learning materials by topic using tags
- Track your coding journey through conversation history

## 🤝 Contributing

Contributions are welcome! Please follow the guidelines in `AGENTS.md` for:
- Phoenix LiveView best practices
- Elixir coding standards
- UI/UX design principles
- Testing strategies

## 📄 License

This project is available for personal and educational use.

## 🙏 Acknowledgments

Built with these amazing technologies:
- [Phoenix Framework](https://www.phoenixframework.org/) - The productive web framework
- [Phoenix LiveView](https://hexdocs.pm/phoenix_live_view) - Real-time server-rendered HTML
- [Elixir](https://elixir-lang.org/) - Scalable and maintainable language
- [OpenAI](https://platform.openai.com/docs) - Powerful AI models
- [Ollama](https://ollama.ai/) - Run LLMs locally

---

<p align="center">
  <strong>Built with ❤️ using Elixir and Phoenix LiveView</strong>
</p>

<p align="center">
  <img src="/docs/images/tech-stack.png" alt="Tech Stack" />
</p>

*👆 Recommended: Banner image showing logos of Elixir, Phoenix, LiveView, OpenAI, and Ollama*

## Resources

- [Phoenix Framework](https://www.phoenixframework.org/)
- [Phoenix LiveView](https://hexdocs.pm/phoenix_live_view)
- [Elixir Documentation](https://elixir-lang.org/docs.html)
- [Tailwind CSS](https://tailwindcss.com/)
- [OpenAI API](https://platform.openai.com/docs)
- [Ollama](https://ollama.ai/)
