defmodule ElixirBearWeb.SolutionsLive do
  use ElixirBearWeb, :live_view
  alias ElixirBear.Solutions
  alias ElixirBear.Chat

  @impl true
  def mount(_params, _session, socket) do
    solutions = Solutions.list_solutions()
    selected_bg = Chat.get_selected_background_image()

    # Extract all unique tags for filtering
    all_topics = extract_all_tags(solutions, "topic")
    all_difficulties = extract_all_tags(solutions, "difficulty")
    all_languages = extract_all_tags(solutions, "language")

    {:ok,
     assign(socket,
       solutions: solutions,
       filtered_solutions: solutions,
       selected_bg: selected_bg,
       all_topics: all_topics,
       all_difficulties: all_difficulties,
       all_languages: all_languages,
       selected_topic: nil,
       selected_difficulty: nil,
       selected_language: nil,
       search_query: "",
       selected_solution: nil
     )}
  end

  @impl true
  def handle_params(%{"id" => id}, _uri, socket) do
    solution = Solutions.get_solution!(String.to_integer(id))
    {:noreply, assign(socket, selected_solution: solution)}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, assign(socket, selected_solution: nil)}
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    filtered = filter_solutions(socket.assigns.solutions, %{
      search_query: query,
      topic: socket.assigns.selected_topic,
      difficulty: socket.assigns.selected_difficulty,
      language: socket.assigns.selected_language
    })

    {:noreply, assign(socket, search_query: query, filtered_solutions: filtered)}
  end

  def handle_event("filter_topic", %{"topic" => topic}, socket) do
    topic = if topic == "", do: nil, else: topic

    filtered = filter_solutions(socket.assigns.solutions, %{
      search_query: socket.assigns.search_query,
      topic: topic,
      difficulty: socket.assigns.selected_difficulty,
      language: socket.assigns.selected_language
    })

    {:noreply, assign(socket, selected_topic: topic, filtered_solutions: filtered)}
  end

  def handle_event("filter_difficulty", %{"difficulty" => difficulty}, socket) do
    difficulty = if difficulty == "", do: nil, else: difficulty

    filtered = filter_solutions(socket.assigns.solutions, %{
      search_query: socket.assigns.search_query,
      topic: socket.assigns.selected_topic,
      difficulty: difficulty,
      language: socket.assigns.selected_language
    })

    {:noreply, assign(socket, selected_difficulty: difficulty, filtered_solutions: filtered)}
  end

  def handle_event("filter_language", %{"language" => language}, socket) do
    language = if language == "", do: nil, else: language

    filtered = filter_solutions(socket.assigns.solutions, %{
      search_query: socket.assigns.search_query,
      topic: socket.assigns.selected_topic,
      difficulty: socket.assigns.selected_difficulty,
      language: language
    })

    {:noreply, assign(socket, selected_language: language, filtered_solutions: filtered)}
  end

  def handle_event("clear_filters", _params, socket) do
    {:noreply,
     assign(socket,
       selected_topic: nil,
       selected_difficulty: nil,
       selected_language: nil,
       search_query: "",
       filtered_solutions: socket.assigns.solutions
     )}
  end

  def handle_event("close_solution_detail", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/solutions")}
  end

  # Private helpers

  defp extract_all_tags(solutions, tag_type) do
    solutions
    |> Enum.flat_map(fn solution ->
      Enum.filter(solution.tags, fn tag -> tag.tag_type == tag_type end)
      |> Enum.map(& &1.tag_value)
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp filter_solutions(solutions, filters) do
    solutions
    |> filter_by_search(filters.search_query)
    |> filter_by_tag(filters.topic, "topic")
    |> filter_by_tag(filters.difficulty, "difficulty")
    |> filter_by_tag(filters.language, "language")
  end

  defp filter_by_search(solutions, query) when query == "" or is_nil(query), do: solutions

  defp filter_by_search(solutions, query) do
    query_lower = String.downcase(query)

    Enum.filter(solutions, fn solution ->
      String.contains?(String.downcase(solution.title || ""), query_lower) or
        String.contains?(String.downcase(solution.user_query), query_lower) or
        String.contains?(
          String.downcase(get_in(solution.metadata, ["description"]) || ""),
          query_lower
        )
    end)
  end

  defp filter_by_tag(solutions, nil, _tag_type), do: solutions

  defp filter_by_tag(solutions, tag_value, tag_type) do
    Enum.filter(solutions, fn solution ->
      Enum.any?(solution.tags, fn tag ->
        tag.tag_type == tag_type and tag.tag_value == tag_value
      end)
    end)
  end

  defp difficulty_badge_class("beginner"), do: "badge-success"
  defp difficulty_badge_class("intermediate"), do: "badge-warning"
  defp difficulty_badge_class("advanced"), do: "badge-error"
  defp difficulty_badge_class(_), do: "badge-neutral"

  @impl true
  def render(assigns) do
    ~H"""
    <div
      class="min-h-screen bg-cover bg-center bg-no-repeat"
      style={
        if @selected_bg,
          do: "background-image: url('/uploads/backgrounds/#{@selected_bg.filename}')",
          else: ""
      }
    >
      <div class="min-h-screen bg-base-100/90 backdrop-blur-sm">
        <div class="navbar bg-base-300/50 backdrop-blur-md sticky top-0 z-50">
          <div class="flex-1">
            <.link navigate={~p"/"} class="btn btn-ghost normal-case text-xl">
              Elixir Bear
            </.link>
            <span class="ml-2 text-sm opacity-70">/ Treasure Trove</span>
          </div>
          <div class="flex-none">
            <.link navigate={~p"/"} class="btn btn-ghost">
              Chat
            </.link>
            <.link navigate={~p"/settings"} class="btn btn-ghost">
              Settings
            </.link>
          </div>
        </div>

        <div class="container mx-auto p-4 max-w-7xl">
          <!-- Header -->
          <div class="mb-6">
            <h1 class="text-3xl font-bold mb-2">Treasure Trove</h1>
            <p class="text-base-content/70">
              Browse and search your saved Elixir learning solutions
            </p>
          </div>

          <!-- Search and Filters -->
          <div class="card bg-base-200/80 backdrop-blur-sm shadow-xl mb-6">
            <div class="card-body">
              <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
                <!-- Search -->
                <div class="form-control">
                  <label class="label">
                    <span class="label-text">Search</span>
                  </label>
                  <input
                    type="text"
                    placeholder="Search titles, questions..."
                    class="input input-bordered w-full"
                    value={@search_query}
                    phx-change="search"
                    name="query"
                  />
                </div>

                <!-- Topic Filter -->
                <div class="form-control">
                  <label class="label">
                    <span class="label-text">Topic</span>
                  </label>
                  <select
                    class="select select-bordered w-full"
                    phx-change="filter_topic"
                    name="topic"
                  >
                    <option value="">All Topics</option>
                    <%= for topic <- @all_topics do %>
                      <option value={topic} selected={topic == @selected_topic}><%= topic %></option>
                    <% end %>
                  </select>
                </div>

                <!-- Difficulty Filter -->
                <div class="form-control">
                  <label class="label">
                    <span class="label-text">Difficulty</span>
                  </label>
                  <select
                    class="select select-bordered w-full"
                    phx-change="filter_difficulty"
                    name="difficulty"
                  >
                    <option value="">All Difficulties</option>
                    <%= for difficulty <- @all_difficulties do %>
                      <option value={difficulty} selected={difficulty == @selected_difficulty}>
                        <%= String.capitalize(difficulty) %>
                      </option>
                    <% end %>
                  </select>
                </div>

                <!-- Language Filter -->
                <div class="form-control">
                  <label class="label">
                    <span class="label-text">Language</span>
                  </label>
                  <select
                    class="select select-bordered w-full"
                    phx-change="filter_language"
                    name="language"
                  >
                    <option value="">All Languages</option>
                    <%= for language <- @all_languages do %>
                      <option value={language} selected={language == @selected_language}>
                        <%= language %>
                      </option>
                    <% end %>
                  </select>
                </div>
              </div>

              <!-- Clear Filters Button -->
              <%= if @selected_topic || @selected_difficulty || @selected_language || @search_query != "" do %>
                <div class="mt-4">
                  <button class="btn btn-sm btn-ghost" phx-click="clear_filters">
                    Clear All Filters
                  </button>
                </div>
              <% end %>
            </div>
          </div>

          <!-- Results Count -->
          <div class="mb-4">
            <p class="text-sm text-base-content/70">
              Showing <%= length(@filtered_solutions) %> of <%= length(@solutions) %> solutions
            </p>
          </div>

          <!-- Solutions Grid -->
          <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            <%= for solution <- @filtered_solutions do %>
              <.link
                navigate={~p"/solutions/#{solution.id}"}
                class="card bg-base-100 shadow-xl hover:shadow-2xl transition-shadow cursor-pointer"
              >
                <div class="card-body">
                  <h2 class="card-title text-lg">
                    <%= solution.title || "Untitled Solution" %>
                  </h2>

                  <p class="text-sm text-base-content/70 line-clamp-2">
                    <%= solution.user_query %>
                  </p>

                  <%= if get_in(solution.metadata, ["description"]) do %>
                    <p class="text-sm text-base-content/60 line-clamp-2 mt-2">
                      <%= get_in(solution.metadata, ["description"]) %>
                    </p>
                  <% end %>

                  <!-- Tags -->
                  <div class="flex flex-wrap gap-2 mt-4">
                    <%= for tag <- Enum.filter(solution.tags, fn t -> t.tag_type == "topic" end) |> Enum.take(3) do %>
                      <span class="badge badge-primary badge-sm"><%= tag.tag_value %></span>
                    <% end %>

                    <%= for tag <- Enum.filter(solution.tags, fn t -> t.tag_type == "difficulty" end) do %>
                      <span class={"badge badge-sm #{difficulty_badge_class(tag.tag_value)}"}>
                        <%= tag.tag_value %>
                      </span>
                    <% end %>
                  </div>

                  <!-- Code Block Count -->
                  <div class="text-xs text-base-content/50 mt-2">
                    <%= length(solution.code_blocks) %> code block(s)
                  </div>
                </div>
              </.link>
            <% end %>
          </div>

          <!-- Empty State -->
          <%= if length(@filtered_solutions) == 0 do %>
            <div class="card bg-base-200/80 backdrop-blur-sm shadow-xl">
              <div class="card-body items-center text-center">
                <h2 class="card-title">No solutions found</h2>
                <p class="text-base-content/70">
                  <%= if length(@solutions) == 0 do %>
                    Start saving solutions from your chat conversations to build your treasure trove!
                  <% else %>
                    Try adjusting your filters or search query.
                  <% end %>
                </p>
                <%= if @selected_topic || @selected_difficulty || @selected_language || @search_query != "" do %>
                  <button class="btn btn-primary mt-4" phx-click="clear_filters">
                    Clear Filters
                  </button>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>
      </div>

      <!-- Solution Detail Modal -->
      <%= if @selected_solution do %>
        <div class="fixed inset-0 bg-black/50 backdrop-blur-sm z-50 flex items-center justify-center p-4">
          <div class="card bg-base-100 shadow-2xl max-w-4xl w-full max-h-[90vh] overflow-hidden flex flex-col">
            <div class="card-body overflow-y-auto">
              <!-- Header -->
              <div class="flex justify-between items-start mb-4">
                <div class="flex-1">
                  <h2 class="card-title text-2xl mb-2">
                    <%= @selected_solution.title || "Untitled Solution" %>
                  </h2>

                  <!-- Tags -->
                  <div class="flex flex-wrap gap-2 mb-4">
                    <%= for tag <- Enum.filter(@selected_solution.tags, fn t -> t.tag_type == "topic" end) do %>
                      <span class="badge badge-primary"><%= tag.tag_value %></span>
                    <% end %>

                    <%= for tag <- Enum.filter(@selected_solution.tags, fn t -> t.tag_type == "difficulty" end) do %>
                      <span class={"badge #{difficulty_badge_class(tag.tag_value)}"}>
                        <%= tag.tag_value %>
                      </span>
                    <% end %>

                    <%= for tag <- Enum.filter(@selected_solution.tags, fn t -> t.tag_type == "language" end) do %>
                      <span class="badge badge-neutral"><%= tag.tag_value %></span>
                    <% end %>
                  </div>
                </div>

                <button class="btn btn-sm btn-circle btn-ghost" phx-click="close_solution_detail">
                  ✕
                </button>
              </div>

              <%= if get_in(@selected_solution.metadata, ["description"]) do %>
                <div class="alert alert-info mb-4">
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    fill="none"
                    viewBox="0 0 24 24"
                    class="stroke-current shrink-0 w-6 h-6"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
                    >
                    </path>
                  </svg>
                  <span><%= get_in(@selected_solution.metadata, ["description"]) %></span>
                </div>
              <% end %>

              <!-- User Question -->
              <div class="mb-6">
                <h3 class="font-bold text-lg mb-2">Question</h3>
                <div class="bg-base-200 p-4 rounded-lg">
                  <%= @selected_solution.user_query %>
                </div>
              </div>

              <!-- Code Blocks -->
              <%= if length(@selected_solution.code_blocks) > 0 do %>
                <div class="mb-6">
                  <h3 class="font-bold text-lg mb-2">Code Examples</h3>
                  <%= for code_block <- Enum.sort_by(@selected_solution.code_blocks, & &1.order) do %>
                    <div class="mb-4">
                      <%= if code_block.description do %>
                        <p class="text-sm text-base-content/70 mb-2"><%= code_block.description %></p>
                      <% end %>
                      <div class="mockup-code">
                        <pre><code class={"language-#{code_block.language}"}><%= code_block.code %></code></pre>
                      </div>
                    </div>
                  <% end %>
                </div>
              <% end %>

              <!-- Full Answer -->
              <div>
                <h3 class="font-bold text-lg mb-2">Full Answer</h3>
                <div class="prose max-w-none">
                  <%= raw(
                    @selected_solution.answer_content
                    |> Earmark.as_html!()
                  ) %>
                </div>
              </div>

              <!-- Metadata -->
              <div class="text-xs text-base-content/50 mt-6 pt-4 border-t border-base-300">
                <p>
                  Saved: <%= Calendar.strftime(@selected_solution.inserted_at, "%B %d, %Y at %I:%M %p") %>
                </p>
              </div>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end
end
