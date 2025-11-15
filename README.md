# ElixirBear

A modern AI chat interface built with Phoenix LiveView that enables conversations with AI models, manages reusable code solutions, and provides a beautiful, customizable user experience.

## Features

### Chat Interface
- **AI Conversations**: Interactive chat with AI models (supports both OpenAI and Ollama)
- **Multi-modal Support**: Attach images, audio files, and code files to your messages
- **Conversation Management**: Create, view, and manage multiple conversation threads
- **Real-time Updates**: LiveView-powered real-time message streaming
- **Background Customization**: Personalize your chat interface with custom background images

### Solutions Management
- **Code Solutions Library**: Store and organize reusable code snippets and solutions
- **Automatic Extraction**: Extract solutions from chat conversations using LLM assistance
- **Tagging System**: Categorize solutions with tags for easy retrieval
- **Smart Router**: AI-powered solution matching to suggest relevant solutions for new queries
- **Code Blocks**: Support for multiple code blocks per solution with syntax highlighting

### File Attachments
Supports a wide variety of file types:
- **Images**: `.jpg`, `.jpeg`, `.png`, `.gif`, `.webp`
- **Audio**: `.mp3`, `.mpga`, `.m4a`, `.wav`
- **Code Files**: `.txt`, `.md`, `.ex`, `.exs`, `.heex`, `.eex`, `.leex`
- **Web Files**: `.js`, `.jsx`, `.ts`, `.tsx`, `.css`, `.scss`, `.html`
- **Config Files**: `.json`, `.xml`, `.yaml`, `.yml`, `.toml`
- **Other Languages**: `.py`, `.rb`, `.java`, `.go`, `.rs`, `.c`, `.cpp`, `.h`, `.hpp`, `.sh`, `.bash`

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

## Usage

Start the Phoenix server:

```bash
mix phx.server
```

Or start it inside IEx for interactive debugging:

```bash
iex -S mix phx.server
```

Visit [`localhost:4000`](http://localhost:4000) in your browser.

### First-time Setup

1. Navigate to Settings (`/settings`) to configure:
   - OpenAI API key (if using OpenAI models)
   - Ollama endpoint (if using local Ollama models)
   - Solution extraction settings
   - Solution router settings

2. Start a new conversation from the home page
3. Begin chatting with your AI assistant!

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

## Project Structure

```
lib/
├── elixir_bear/               # Core business logic
│   ├── chat/                  # Chat domain (conversations, messages, settings)
│   ├── solutions/             # Solutions domain (solutions, tags, extraction)
│   ├── ollama.ex             # Ollama API integration
│   ├── openai.ex             # OpenAI API integration
│   └── conversation_worker.ex # Background worker for chat processing
├── elixir_bear_web/          # Web interface
│   ├── live/                 # LiveView modules
│   │   ├── chat_live.ex     # Main chat interface
│   │   ├── solutions_live.ex # Solutions library
│   │   └── settings_live.ex  # Settings page
│   ├── components/           # Reusable components
│   └── router.ex            # Application routes
```

## Configuration

Key configuration files:
- `config/config.exs` - Application configuration
- `config/dev.exs` - Development environment settings
- `config/prod.exs` - Production environment settings
- `AGENTS.md` - Development guidelines and coding standards

## Contributing

When contributing to this project, please follow the guidelines in `AGENTS.md` for:
- Phoenix LiveView best practices
- Elixir coding standards
- UI/UX design principles
- Testing strategies

## License

This project is available for personal and educational use.

## Resources

- [Phoenix Framework](https://www.phoenixframework.org/)
- [Phoenix LiveView](https://hexdocs.pm/phoenix_live_view)
- [Elixir Documentation](https://elixir-lang.org/docs.html)
- [Tailwind CSS](https://tailwindcss.com/)
- [OpenAI API](https://platform.openai.com/docs)
- [Ollama](https://ollama.ai/)
