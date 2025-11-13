defmodule ElixirBear.Chat do
  @moduledoc """
  The Chat context.
  """

  import Ecto.Query, warn: false
  alias ElixirBear.Repo

  alias ElixirBear.Chat.{Setting, Conversation, Message}
  alias ElixirBear.BackgroundImage

  # Settings

  @doc """
  Gets a setting by key.
  """
  def get_setting(key) do
    Repo.get_by(Setting, key: key)
  end

  @doc """
  Gets a setting value by key. Returns nil if not found or empty.
  """
  def get_setting_value(key) do
    case get_setting(key) do
      %Setting{value: value} when value != "" -> value
      _ -> nil
    end
  end

  @doc """
  Updates a setting.
  """
  def update_setting(key, value) do
    case get_setting(key) do
      nil ->
        %Setting{}
        |> Setting.changeset(%{key: key, value: value})
        |> Repo.insert()

      setting ->
        setting
        |> Setting.changeset(%{value: value})
        |> Repo.update()
    end
  end

  # Conversations

  @doc """
  Returns the list of conversations.
  """
  def list_conversations do
    Conversation
    |> order_by([c], desc: c.updated_at)
    |> Repo.all()
  end

  @doc """
  Gets a single conversation with messages.
  """
  def get_conversation!(id) do
    Conversation
    |> Repo.get!(id)
    |> Repo.preload(:messages)
  end

  @doc """
  Creates a conversation.
  """
  def create_conversation(attrs \\ %{}) do
    %Conversation{}
    |> Conversation.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a conversation.
  """
  def update_conversation(%Conversation{} = conversation, attrs) do
    conversation
    |> Conversation.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a conversation.
  """
  def delete_conversation(%Conversation{} = conversation) do
    Repo.delete(conversation)
  end

  # Messages

  @doc """
  Creates a message.
  """
  def create_message(attrs \\ %{}) do
    %Message{}
    |> Message.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets messages for a conversation.
  """
  def list_messages(conversation_id) do
    Message
    |> where([m], m.conversation_id == ^conversation_id)
    |> order_by([m], asc: m.inserted_at)
    |> Repo.all()
  end

  @doc """
  Gets the current system prompt from settings or uses the conversation's system prompt.
  """
  def get_system_prompt(conversation) do
    case conversation.system_prompt do
      nil -> get_setting_value("system_prompt")
      "" -> get_setting_value("system_prompt")
      prompt -> prompt
    end
  end

  @doc """
  Generates a title for a conversation based on the first user message.
  """
  def generate_conversation_title(conversation_id) do
    message =
      Message
      |> where([m], m.conversation_id == ^conversation_id and m.role == "user")
      |> order_by([m], asc: m.inserted_at)
      |> limit(1)
      |> Repo.one()

    case message do
      nil ->
        "New Conversation"

      %Message{content: content} ->
        content
        |> String.slice(0..50)
        |> String.trim()
        |> then(fn title ->
          if String.length(content) > 50, do: title <> "...", else: title
        end)
    end
  end

  # Background Images

  @doc """
  Returns the list of background images.
  """
  def list_background_images do
    BackgroundImage
    |> order_by([b], desc: b.inserted_at)
    |> Repo.all()
  end

  @doc """
  Gets a single background image.
  """
  def get_background_image!(id), do: Repo.get!(BackgroundImage, id)

  @doc """
  Gets the currently selected background image.
  """
  def get_selected_background_image do
    BackgroundImage
    |> where([b], b.is_selected == true)
    |> Repo.one()
  end

  @doc """
  Creates a background image.
  """
  def create_background_image(attrs \\ %{}) do
    %BackgroundImage{}
    |> BackgroundImage.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Selects a background image and deselects all others.
  """
  def select_background_image(id) do
    Repo.transaction(fn ->
      # Deselect all images
      BackgroundImage
      |> Repo.update_all(set: [is_selected: false])

      # Select the chosen image
      background_image = get_background_image!(id)
      background_image
      |> BackgroundImage.changeset(%{is_selected: true})
      |> Repo.update!()
    end)
  end

  @doc """
  Deletes a background image.
  """
  def delete_background_image(%BackgroundImage{} = background_image) do
    Repo.delete(background_image)
  end
end
