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
       selected_solution: nil,
       show_edit_modal: false,
       edit_solution: nil,
       show_delete_modal: false,
       delete_solution: nil
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

  def handle_event("open_edit_modal", %{"id" => id}, socket) do
    solution = Solutions.get_solution!(String.to_integer(id))
    {:noreply, assign(socket, show_edit_modal: true, edit_solution: solution)}
  end

  def handle_event("close_edit_modal", _params, socket) do
    {:noreply, assign(socket, show_edit_modal: false, edit_solution: nil)}
  end

  def handle_event("update_edit_title", %{"value" => title}, socket) do
    updated_solution = Map.put(socket.assigns.edit_solution, :title, title)
    {:noreply, assign(socket, edit_solution: updated_solution)}
  end

  def handle_event("update_edit_description", %{"value" => description}, socket) do
    updated_solution =
      update_in(socket.assigns.edit_solution.metadata, fn meta ->
        Map.put(meta || %{}, "description", description)
      end)
    {:noreply, assign(socket, edit_solution: updated_solution)}
  end

  def handle_event("update_edit_answer", %{"value" => answer}, socket) do
    updated_solution = Map.put(socket.assigns.edit_solution, :answer_content, answer)
    {:noreply, assign(socket, edit_solution: updated_solution)}
  end

  def handle_event("update_edit_user_query", %{"value" => query}, socket) do
    updated_solution = Map.put(socket.assigns.edit_solution, :user_query, query)
    {:noreply, assign(socket, edit_solution: updated_solution)}
  end

  def handle_event("update_code_block", %{"id" => id, "value" => code}, socket) do
    block_id = String.to_integer(id)
    updated_solution =
      update_in(socket.assigns.edit_solution.code_blocks, fn blocks ->
        Enum.map(blocks, fn block ->
          if block.id == block_id do
            Map.put(block, :code, code)
          else
            block
          end
        end)
      end)
    {:noreply, assign(socket, edit_solution: updated_solution)}
  end

  def handle_event("update_code_block_language", %{"id" => id, "value" => language}, socket) do
    block_id = String.to_integer(id)
    updated_solution =
      update_in(socket.assigns.edit_solution.code_blocks, fn blocks ->
        Enum.map(blocks, fn block ->
          if block.id == block_id do
            Map.put(block, :language, language)
          else
            block
          end
        end)
      end)
    {:noreply, assign(socket, edit_solution: updated_solution)}
  end

  def handle_event("delete_code_block", %{"id" => id}, socket) do
    block_id = String.to_integer(id)

    # Delete from database
    block = Enum.find(socket.assigns.edit_solution.code_blocks, fn b -> b.id == block_id end)
    if block do
      Solutions.delete_code_block(block)
    end

    # Update UI
    updated_solution =
      update_in(socket.assigns.edit_solution.code_blocks, fn blocks ->
        Enum.reject(blocks, fn block -> block.id == block_id end)
      end)
    {:noreply, assign(socket, edit_solution: updated_solution)}
  end

  def handle_event("save_edit", _params, socket) do
    solution = socket.assigns.edit_solution

    # Update solution
    solution_result = Solutions.update_solution(solution, %{
      title: solution.title,
      metadata: solution.metadata,
      answer_content: solution.answer_content,
      user_query: solution.user_query
    })

    # Update code blocks
    code_blocks_result =
      Enum.reduce_while(solution.code_blocks, {:ok, []}, fn block, {:ok, acc} ->
        case Solutions.update_code_block(block, %{
          code: block.code,
          language: block.language
        }) do
          {:ok, updated_block} -> {:cont, {:ok, [updated_block | acc]}}
          {:error, changeset} -> {:halt, {:error, changeset}}
        end
      end)

    case {solution_result, code_blocks_result} do
      {{:ok, _updated}, {:ok, _blocks}} ->
        solutions = Solutions.list_solutions()
        filtered = filter_solutions(solutions, %{
          search_query: socket.assigns.search_query,
          topic: socket.assigns.selected_topic,
          difficulty: socket.assigns.selected_difficulty,
          language: socket.assigns.selected_language
        })

        {:noreply,
         socket
         |> assign(solutions: solutions, filtered_solutions: filtered)
         |> assign(show_edit_modal: false, edit_solution: nil)
         |> put_flash(:info, "Potion updated successfully!")}

      _ ->
        {:noreply, put_flash(socket, :error, "Failed to update potion")}
    end
  end

  def handle_event("open_delete_modal", %{"id" => id}, socket) do
    solution = Solutions.get_solution!(String.to_integer(id))
    {:noreply, assign(socket, show_delete_modal: true, delete_solution: solution)}
  end

  def handle_event("close_delete_modal", _params, socket) do
    {:noreply, assign(socket, show_delete_modal: false, delete_solution: nil)}
  end

  def handle_event("confirm_delete", _params, socket) do
    solution = socket.assigns.delete_solution

    case Solutions.delete_solution(solution) do
      {:ok, _deleted} ->
        solutions = Solutions.list_solutions()
        filtered = filter_solutions(solutions, %{
          search_query: socket.assigns.search_query,
          topic: socket.assigns.selected_topic,
          difficulty: socket.assigns.selected_difficulty,
          language: socket.assigns.selected_language
        })

        # Refresh tag lists
        all_topics = extract_all_tags(solutions, "topic")
        all_difficulties = extract_all_tags(solutions, "difficulty")
        all_languages = extract_all_tags(solutions, "language")

        {:noreply,
         socket
         |> assign(
           solutions: solutions,
           filtered_solutions: filtered,
           all_topics: all_topics,
           all_difficulties: all_difficulties,
           all_languages: all_languages
         )
         |> assign(show_delete_modal: false, delete_solution: nil, selected_solution: nil)
         |> push_patch(to: ~p"/solutions")
         |> put_flash(:info, "Potion deleted successfully!")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to delete potion")}
    end
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
            <span class="ml-2 text-sm opacity-70">/ Potion Shelf</span>
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
            <h1 class="text-3xl font-bold mb-2">Potion Shelf</h1>
            <p class="text-base-content/70">
              Browse and search your saved Elixir learning potions
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
                  <form phx-change="search">
                    <input
                      type="text"
                      placeholder="Search titles, questions..."
                      class="input input-bordered w-full"
                      value={@search_query}
                      name="query"
                    />
                  </form>
                </div>

                <!-- Topic Filter -->
                <div class="form-control">
                  <label class="label">
                    <span class="label-text">Topic</span>
                  </label>
                  <form phx-change="filter_topic">
                    <select class="select select-bordered w-full" name="topic">
                      <option value="">All Topics</option>
                      <%= for topic <- @all_topics do %>
                        <option value={topic} selected={topic == @selected_topic}><%= topic %></option>
                      <% end %>
                    </select>
                  </form>
                </div>

                <!-- Difficulty Filter -->
                <div class="form-control">
                  <label class="label">
                    <span class="label-text">Difficulty</span>
                  </label>
                  <form phx-change="filter_difficulty">
                    <select class="select select-bordered w-full" name="difficulty">
                      <option value="">All Difficulties</option>
                      <%= for difficulty <- @all_difficulties do %>
                        <option value={difficulty} selected={difficulty == @selected_difficulty}>
                          <%= String.capitalize(difficulty) %>
                        </option>
                      <% end %>
                    </select>
                  </form>
                </div>

                <!-- Language Filter -->
                <div class="form-control">
                  <label class="label">
                    <span class="label-text">Language</span>
                  </label>
                  <form phx-change="filter_language">
                    <select class="select select-bordered w-full" name="language">
                      <option value="">All Languages</option>
                      <%= for language <- @all_languages do %>
                        <option value={language} selected={language == @selected_language}>
                          <%= language %>
                        </option>
                      <% end %>
                    </select>
                  </form>
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
              Showing <%= length(@filtered_solutions) %> of <%= length(@solutions) %> potions
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
                    <%= solution.title || "Untitled Potion" %>
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
                <h2 class="card-title">No potions found</h2>
                <p class="text-base-content/70">
                  <%= if length(@solutions) == 0 do %>
                    Start saving potions from your chat conversations to build your potion shelf!
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
                    <%= @selected_solution.title || "Untitled Potion" %>
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

              <!-- Action Buttons -->
              <div class="flex gap-2 mb-4">
                <button
                  class="btn btn-sm btn-primary gap-2"
                  phx-click="open_edit_modal"
                  phx-value-id={@selected_solution.id}
                >
                  <svg
                    class="w-4 h-4"
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z"
                    />
                  </svg>
                  Edit Potion
                </button>
                <button
                  class="btn btn-sm btn-error gap-2"
                  phx-click="open_delete_modal"
                  phx-value-id={@selected_solution.id}
                >
                  <svg
                    class="w-4 h-4"
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"
                    />
                  </svg>
                  Delete Potion
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

      <!-- Edit Modal -->
      <%= if @show_edit_modal && @edit_solution do %>
        <div class="fixed inset-0 bg-black/50 backdrop-blur-sm z-50 flex items-center justify-center p-4">
          <div class="card bg-base-100 shadow-2xl max-w-5xl w-full max-h-[90vh] overflow-hidden flex flex-col">
            <div class="card-body overflow-y-auto">
              <h2 class="card-title text-2xl mb-4">Edit Potion</h2>

              <!-- Title -->
              <div class="form-control mb-4">
                <label class="label">
                  <span class="label-text font-semibold">Title</span>
                </label>
                <input
                  type="text"
                  class="input input-bordered w-full"
                  value={@edit_solution.title}
                  phx-blur="update_edit_title"
                />
              </div>

              <!-- Description -->
              <div class="form-control mb-4">
                <label class="label">
                  <span class="label-text font-semibold">Description</span>
                </label>
                <textarea
                  class="textarea textarea-bordered w-full"
                  rows="3"
                  phx-blur="update_edit_description"
                ><%= get_in(@edit_solution.metadata, ["description"]) || "" %></textarea>
              </div>

              <!-- User Question -->
              <div class="form-control mb-4">
                <label class="label">
                  <span class="label-text font-semibold">Question</span>
                </label>
                <textarea
                  class="textarea textarea-bordered w-full"
                  rows="3"
                  phx-blur="update_edit_user_query"
                ><%= @edit_solution.user_query %></textarea>
              </div>

              <!-- Answer Content -->
              <div class="form-control mb-4">
                <label class="label">
                  <span class="label-text font-semibold">Answer Content (Markdown)</span>
                </label>
                <textarea
                  class="textarea textarea-bordered w-full font-mono text-sm"
                  rows="10"
                  phx-blur="update_edit_answer"
                ><%= @edit_solution.answer_content %></textarea>
              </div>

              <!-- Code Blocks -->
              <%= if length(@edit_solution.code_blocks) > 0 do %>
                <div class="mb-4">
                  <label class="label">
                    <span class="label-text font-semibold">Code Blocks</span>
                  </label>
                  <div class="space-y-4">
                    <%= for block <- Enum.sort_by(@edit_solution.code_blocks, & &1.order) do %>
                      <div class="card bg-base-200 shadow">
                        <div class="card-body p-4">
                          <div class="flex justify-between items-center mb-2">
                            <div class="form-control flex-1 mr-4">
                              <label class="label py-1">
                                <span class="label-text text-xs">Language</span>
                              </label>
                              <input
                                type="text"
                                class="input input-bordered input-sm w-full max-w-xs"
                                value={block.language || ""}
                                phx-blur="update_code_block_language"
                                phx-value-id={block.id}
                              />
                            </div>
                            <button
                              class="btn btn-sm btn-error gap-2"
                              phx-click="delete_code_block"
                              phx-value-id={block.id}
                            >
                              <svg
                                class="w-4 h-4"
                                fill="none"
                                stroke="currentColor"
                                viewBox="0 0 24 24"
                              >
                                <path
                                  stroke-linecap="round"
                                  stroke-linejoin="round"
                                  stroke-width="2"
                                  d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"
                                />
                              </svg>
                              Delete
                            </button>
                          </div>
                          <textarea
                            class="textarea textarea-bordered w-full font-mono text-sm"
                            rows="8"
                            phx-blur="update_code_block"
                            phx-value-id={block.id}
                          ><%= block.code %></textarea>
                        </div>
                      </div>
                    <% end %>
                  </div>
                </div>
              <% end %>

              <!-- Action Buttons -->
              <div class="flex gap-2 justify-end pt-4 border-t border-base-300">
                <button class="btn btn-ghost" phx-click="close_edit_modal">
                  Cancel
                </button>
                <button class="btn btn-primary" phx-click="save_edit">
                  Save Changes
                </button>
              </div>
            </div>
          </div>
        </div>
      <% end %>

      <!-- Delete Confirmation Modal -->
      <%= if @show_delete_modal && @delete_solution do %>
        <div class="fixed inset-0 bg-black/50 backdrop-blur-sm z-50 flex items-center justify-center p-4">
          <div class="card bg-base-100 shadow-2xl max-w-md w-full">
            <div class="card-body">
              <h2 class="card-title text-2xl mb-4 text-error">Delete Potion?</h2>

              <div class="alert alert-warning mb-4">
                <svg
                  xmlns="http://www.w3.org/2000/svg"
                  class="stroke-current shrink-0 h-6 w-6"
                  fill="none"
                  viewBox="0 0 24 24"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"
                  />
                </svg>
                <span>
                  This action cannot be undone. This will permanently delete the potion
                  "<strong><%= @delete_solution.title || "Untitled Potion" %></strong>".
                </span>
              </div>

              <div class="flex gap-2 justify-end">
                <button class="btn btn-ghost" phx-click="close_delete_modal">
                  Cancel
                </button>
                <button class="btn btn-error" phx-click="confirm_delete">
                  Delete Permanently
                </button>
              </div>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end
end
