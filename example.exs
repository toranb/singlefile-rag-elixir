Application.put_env(:sample, PhoenixDemo.Endpoint,
  http: [ip: {0, 0, 0, 0}, port: 8080],
  server: true,
  live_view: [signing_salt: "bumblebee"],
  secret_key_base: String.duplicate("b", 64),
  pubsub_server: PhoenixDemo.PubSub
)

Application.put_env(:replicate, :replicate_api_token, System.get_env("REPLICATE_API_TOKEN"))

Mix.install([
  {:plug_cowboy, "~> 2.6"},
  {:jason, "~> 1.4"},
  {:phoenix, "~> 1.7.0"},
  {:phoenix_live_view, "~> 0.18.18"},
  {:phoenix_ecto, "~> 4.4"},
  {:ecto_sql, "~> 3.10"},
  {:postgrex, ">= 0.0.0"},
  {:replicate, "~> 1.1.1"},
  {:pgvector, "~> 0.2.0"},
  # Bumblebee and friends
  {:bumblebee, "~> 0.4.2"},
  {:exla, "~> 0.6"},
  {:nx, "~> 0.6"}
])

Postgrex.Types.define(PhoenixDemo.PostgrexTypes, [Pgvector.Extensions.Vector] ++ Ecto.Adapters.Postgres.extensions(), [])

Application.put_env(:sample, PhoenixDemo.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "demo_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10,
  types: PhoenixDemo.PostgrexTypes
)

Application.put_env(:nx, :default_backend, EXLA.Backend)

defmodule PhoenixDemo.User do
  use Ecto.Schema

  import Ecto.Changeset

  schema "users" do
    field(:name, :string)

    has_many(:messages, PhoenixDemo.Message)

    timestamps()
  end

  @required_attrs [:name]

  def changeset(user, params \\ %{}) do
    user
    |> cast(params, @required_attrs)
    |> validate_required(@required_attrs)
  end
end

defmodule PhoenixDemo.Thread do
  use Ecto.Schema

  import Ecto.Changeset

  schema "threads" do
    field(:title, :string)

    has_many(:messages, PhoenixDemo.Message, preload_order: [asc: :inserted_at])

    timestamps()
  end

  @required_attrs [:title]

  def changeset(thread, params \\ %{}) do
    thread
    |> cast(params, @required_attrs)
    |> validate_required(@required_attrs)
  end
end

defmodule PhoenixDemo.Message do
  use Ecto.Schema

  import Ecto.Query
  import Ecto.Changeset
  import Pgvector.Ecto.Query

  alias __MODULE__

  schema "messages" do
    field(:text, :string)
    field(:embedding, Pgvector.Ecto.Vector)

    belongs_to(:thread, PhoenixDemo.Thread)
    belongs_to(:user, PhoenixDemo.User)

    timestamps()
  end

  @required_attrs [:thread_id, :user_id, :text]
  @optional_attrs [:embedding]

  def changeset(message, params \\ %{}) do
    message
    |> cast(params, @required_attrs ++ @optional_attrs)
    |> validate_required(@required_attrs)
  end

  def search(embedding) do
    PhoenixDemo.Repo.all(
      from i in Message, order_by: max_inner_product(i.embedding, ^embedding), limit: 1
    )
    |> List.first()
  end
end

defmodule PhoenixDemo.Replicate do
  def generate_prompt(question, thread) do
    context =
      thread.messages
      |> Enum.reduce("", fn message, acc ->
        if String.length(acc) == 0 do
          message.text
        else
          acc <> ", " <> message.text
        end
      end)

    """
    [INST] <<SYS>>
    You are an assistant for question-answering tasks. Use the following pieces of retrieved context to answer the question.
    If you do not know the answer, just say that you don't know. Use two sentences maximum and keep the answer concise.
    <</SYS>>
    Question: #{question}
    Context: #{context}[/INST]
    """
  end
end

defmodule PhoenixDemo.Layouts do
  use Phoenix.Component

  def render("live.html", assigns) do
    ~H"""
    <script src="https://cdn.jsdelivr.net/npm/phoenix@1.7.0-rc.0/priv/static/phoenix.min.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/phoenix_live_view@0.18.3/priv/static/phoenix_live_view.min.js"></script>
    <script>
      const liveSocket = new window.LiveView.LiveSocket("/live", window.Phoenix.Socket);
      liveSocket.connect();
    </script>
    <script src="https://cdn.tailwindcss.com">
    </script>
    <div class="relative flex flex-col min-h-screen bg-gray-100 border-t-8 border-purple-600">
    <%= @inner_content %>
    </div>
    """
  end
end

defmodule PhoenixDemo.ErrorView do
  def render(_, _), do: "error"
end

defmodule PhoenixDemo.SampleLive do
  use Phoenix.LiveView, layout: {PhoenixDemo.Layouts, :live}

  alias PhoenixDemo.Repo

  @impl true
  def mount(_, _, socket) do
    model = Replicate.Models.get!("meta/llama-2-7b-chat")
    version = Replicate.Models.get_latest_version!(model)
    user = PhoenixDemo.User |> Repo.get_by!(name: "toran billups")
    threads = PhoenixDemo.Thread |> Repo.all() |> Repo.preload(messages: :user)

    socket = socket |> assign(version: version, user: user, threads: threads, result: nil, text: nil, loading: false, selected: nil, query: nil, transformer: nil, llama: nil)

    {:ok, socket}
  end

  @impl true
  def handle_event("select_thread", %{"id" => thread_id}, socket) do
    thread = socket.assigns.threads |> Enum.find(& &1.id == String.to_integer(thread_id))
    socket = socket |> assign(selected: thread, result: nil)

    {:noreply, socket}
  end

  @impl true
  def handle_event("change_text", %{"message" => text}, socket) do
    socket = socket |> assign(text: text)

    {:noreply, socket}
  end

  @impl true
  def handle_event("add_message", %{"message" => text}, socket) do
    user_id = socket.assigns.user.id
    selected_id = socket.assigns.selected.id

    message =
      %PhoenixDemo.Message{}
      |> PhoenixDemo.Message.changeset(%{text: text, thread_id: selected_id, user_id: user_id})
      |> Repo.insert!()

    transformer =
      Task.async(fn ->
        {message.id, Nx.Serving.batched_run(SentenceTransformer, text)}
      end)

    threads = PhoenixDemo.Thread |> Repo.all() |> Repo.preload(messages: :user)
    selected = threads |> Enum.find(& &1.id == selected_id)
    socket = socket |> assign(threads: threads, selected: selected, transformer: transformer, text: nil)

    {:noreply, socket}
  end

  @impl true
  def handle_event("query", %{"search" => _value}, %{assigns: %{loading: true}} = socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("query", %{"search" => value}, %{assigns: %{loading: false}} = socket) do
    query =
      Task.async(fn ->
        {value, Nx.Serving.batched_run(SentenceTransformer, value)}
      end)

    socket = socket |> assign(query: query, loading: true, result: nil)

    {:noreply, socket}
  end

  @impl true
  def handle_info({ref, {message_id, %{embedding: embedding}}}, socket) when socket.assigns.transformer.ref == ref do
    PhoenixDemo.Message
    |> Repo.get!(message_id)
    |> PhoenixDemo.Message.changeset(%{embedding: embedding})
    |> Repo.update!()

    socket = socket |> assign(transformer: nil)

    {:noreply, socket}
  end

  @impl true
  def handle_info({ref, {question, %{embedding: embedding}}}, socket) when socket.assigns.query.ref == ref do
    %PhoenixDemo.Message{thread_id: thread_id} = PhoenixDemo.Message.search(embedding)

    thread = socket.assigns.threads |> Enum.find(& &1.id == thread_id)
    prompt = PhoenixDemo.Replicate.generate_prompt(question, thread)
    version = socket.assigns.version

    llama =
      Task.async(fn ->
        {:ok, prediction} = Replicate.Predictions.create(version, %{prompt: prompt})
        {thread.id, Replicate.Predictions.wait(prediction)}
      end)

    # llama =
    #   Task.async(fn ->
    #     {thread.id, Nx.Serving.batched_run(ChatServing, prompt)}
    #   end)

    {:noreply, assign(socket, query: nil, llama: llama, selected: thread)}
  end

  @impl true
  def handle_info({ref, {thread_id, {:ok, prediction}}}, socket) when socket.assigns.llama.ref == ref do
    result = Enum.join(prediction.output)
    thread = socket.assigns.threads |> Enum.find(& &1.id == thread_id)

    {:noreply, assign(socket, llama: nil, result: result, selected: thread, loading: false)}
  end

  @impl true
  def handle_info({ref, {thread_id, %{results: [%{text: text}]}}}, socket) when socket.assigns.llama.ref == ref do
    [_, result] = String.split(text, "[/INST]\n")

    thread = socket.assigns.threads |> Enum.find(& &1.id == thread_id)

    {:noreply, assign(socket, llama: nil, result: result, selected: thread, loading: false)}
  end

  @impl true
  def handle_info(_, socket) do
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col grow px-2 sm:px-4 lg:px-8 py-10">
      <form class="mt-4" phx-submit="query">
        <label class="relative flex items-center">
          <input id="search" name="search" type="search" placeholder="ask a question ..." class="block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 text-sm placeholder:text-gray-400 text-gray-900 pl-8" autofocus>
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true" class="absolute left-2 h-5 text-gray-500">
            <path fill-rule="evenodd" d="M8 4a4 4 0 100 8 4 4 0 000-8zM2 8a6 6 0 1110.89 3.476l4.817 4.817a1 1 0 01-1.414 1.414l-4.816-4.816A6 6 0 012 8z" clip-rule="evenodd"></path>
          </svg>
        </label>
      </form>
      <div class="flex flex-col grow relative -mb-8 mt-2 mt-2">
        <div class="absolute inset-0 gap-4">
          <div class="h-full flex flex-col bg-white shadow-sm border rounded-md">
            <div class="grid-cols-4 h-full grid divide-x">
              <div class="flex flex-col hover:scroll-auto">
                <div class="flex flex-col justify-stretch grow p-2">
                  <%= for thread <- @threads do %>
                  <div id={"thread-#{thread.id}"} class="flex flex-col justify-stretch">
                    <button type="button" phx-click="select_thread" phx-value-id={thread.id} class={"flex p-4 items-center justify-between rounded-md hover:bg-gray-100 text-sm text-left text-gray-700 outline-none #{if @selected && @selected.id == thread.id, do: "bg-gray-100"}"}>
                      <div class="flex flex-col overflow-hidden">
                        <div class="inline-flex items-center space-x-1 font-medium text-sm text-gray-800">
                          <div class="p-1 rounded-full bg-gray-200 text-gray-900">
                            <div class="rounded-full w-9 h-9 min-w-9 flex justify-center items-center text-base bg-purple-600 text-white capitalize"><%= String.first(thread.title) %></div>
                          </div>
                          <span class="pl-1 capitalize"><%= thread.title %></span>
                        </div>
                        <div class="hidden mt-1 inline-flex justify-start items-center flex-nowrap text-xs text-gray-500 overflow-hidden">
                          <span class="whitespace-nowrap text-ellipsis overflow-hidden"><%= thread.title %></span>
                          <span class="mx-1 inline-flex rounded-full w-0.5 h-0.5 min-w-0.5 bg-gray-500"></span>
                        </div>
                      </div>
                    </button>
                  </div>
                  <% end %>
                </div>
              </div>
              <div class={"block relative #{if @loading || !is_nil(@result), do: "col-span-2", else: "col-span-3"}"}>
                <div class="flex absolute inset-0 flex-col">
                  <div class="relative flex grow overflow-y-hidden">
                    <div :if={!is_nil(@selected)} class="pt-4 pb-1 px-4 flex flex-col grow overflow-y-auto">
                      <%= for message <- @selected.messages do %>
                      <div :if={message.user_id != @user.id} id={"message-#{message.id}"} class="my-2 flex flex-row justify-start space-x-1 self-start items-start">
                        <div class="hidden rounded-full w-9 h-9 min-w-9 flex justify-center items-center text-base bg-gray-100 text-gray-900 capitalize"><%= String.first(message.user.name) %></div>
                        <div class="flex flex-col space-y-0.5 self-start items-start">
                          <div class="bg-gray-200 text-gray-900 ml-0 mr-12 py-2 px-3 inline-flex text-sm rounded-lg whitespace-pre-wrap"><%= message.text %></div>
                          <div class="mx-1 text-xs text-gray-500"><%= Calendar.strftime(message.inserted_at, "%B %d, %-I:%M %p") %></div>
                        </div>
                      </div>
                      <div :if={message.user_id == @user.id} id={"message-#{message.id}"} class="my-2 flex flex-row justify-start space-x-1 self-end items-end">
                        <div class="flex flex-col space-y-0.5 self-end items-end">
                          <div class="bg-purple-600 text-gray-50 ml-12 mr-0 py-2 px-3 inline-flex text-sm rounded-lg whitespace-pre-wrap"><%= message.text %></div>
                          <div class="mx-1 text-xs text-gray-500"><%= Calendar.strftime(message.inserted_at, "%B %d, %-I:%M %p") %></div>
                        </div>
                      </div>
                      <% end %>
                    </div>
                  </div>
                  <form class="px-4 py-2 flex flex-row items-end gap-x-2" phx-submit="add_message" phx-change="change_text">
                    <div class="flex flex-col grow rounded-md border border-gray-300">
                      <div class="relative flex grow">
                        <input id="message" name="message" value={@text} class="block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 text-sm placeholder:text-gray-400 text-gray-900" placeholder="Aa" type="text" />
                      </div>
                    </div>
                    <div class="ml-1">
                      <button type="submit" class="flex items-center justify-center h-10 w-10 rounded-full bg-gray-200 hover:bg-gray-300 text-gray-500">
                        <svg class="w-5 h-5 transform rotate-90 -mr-px" fill="none" stroke="currentColor" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 19l9 2-9-18-9 18 9-2zm0 0v-8"></path>
                        </svg>
                      </button>
                    </div>
                  </form>
                </div>
              </div>
              <div :if={!is_nil(@selected) && @loading} class="block col-span-1 relative">
                <div class="flex absolute inset-0 flex-col justify-stretch">
                  <div class="p-4">
                    <div role="status" class="max-w-sm animate-pulse">
                        <div class="h-2.5 bg-gray-100 rounded-full dark:bg-gray-200 w-40 mb-5"></div>
                        <div class="h-2 bg-gray-100 rounded-full dark:bg-gray-200 max-w-[360px] mb-3"></div>
                        <div class="h-2 bg-gray-100 rounded-full dark:bg-gray-200 mb-2.5"></div>
                        <div class="h-2 bg-gray-100 rounded-full dark:bg-gray-200 max-w-[250px] mb-3"></div>
                        <div class="h-2 bg-gray-100 rounded-full dark:bg-gray-200 max-w-[300px] mb-3"></div>
                        <div class="h-2 bg-gray-100 rounded-full dark:bg-gray-200 max-w-[200px]"></div>
                        <div class="py-3.5"></div>
                        <div class="h-2 bg-gray-100 rounded-full dark:bg-gray-200 max-w-[360px] mb-3"></div>
                        <div class="h-2 bg-gray-100 rounded-full dark:bg-gray-200 mb-3"></div>
                        <div class="h-2 bg-gray-100 rounded-full dark:bg-gray-200 max-w-[220px]"></div>
                        <div class="py-3.5"></div>
                        <div class="h-2 bg-gray-100 rounded-full dark:bg-gray-200 max-w-[360px] mb-3"></div>
                        <div class="h-2 bg-gray-100 rounded-full dark:bg-gray-200 mb-3"></div>
                        <div class="h-2 bg-gray-100 rounded-full dark:bg-gray-200 max-w-[250px] mb-3"></div>
                        <div class="h-2 bg-gray-100 rounded-full dark:bg-gray-200 max-w-[300px] mb-3"></div>
                        <div class="h-2 bg-gray-100 rounded-full dark:bg-gray-200 max-w-[200px]"></div>
                        <span class="sr-only">Loading...</span>
                    </div>
                  </div>
                </div>
              </div>
              <div :if={!is_nil(@result)} class="block col-span-1 relative">
                <div class="flex absolute inset-0 flex-col justify-stretch">
                  <div class="p-4 space-y-6 flex flex-col grow overflow-y-auto"><div>
                  <p class="font-medium text-sm text-gray-900">Summary</p>
                  <p class="pt-4 text-sm text-gray-900"><%= @result %></p>
                </div>
              </div>
            </div>
          </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end

defmodule PhoenixDemo.Repo do
  use Ecto.Repo,
    otp_app: :sample,
    adapter: Ecto.Adapters.Postgres
end

defmodule PhoenixDemo.Router do
  use Phoenix.Router

  import Phoenix.LiveView.Router

  pipeline :browser do
    plug(:accepts, ["html"])
  end

  scope "/", PhoenixDemo do
    pipe_through(:browser)

    live("/", SampleLive, :index)
  end
end

defmodule PhoenixDemo.Endpoint do
  use Phoenix.Endpoint, otp_app: :sample

  socket("/live", Phoenix.LiveView.Socket)
  plug(PhoenixDemo.Router)
end

# Application startup
Nx.default_backend(EXLA.Backend)

hf_repo = "thenlper/gte-base"
{:ok, model_info} = Bumblebee.load_model({:hf, hf_repo})
{:ok, tokenizer} = Bumblebee.load_tokenizer({:hf, hf_repo})

serving =
  Bumblebee.Text.TextEmbedding.text_embedding(model_info, tokenizer,
    output_pool: :mean_pooling,
    output_attribute: :hidden_state,
    embedding_processor: :l2_norm,
    compile: [batch_size: 32, sequence_length: [32]],
    defn_options: [compiler: EXLA]
  )

{:ok, _} =
  Supervisor.start_link(
    [
      {Phoenix.PubSub, name: PhoenixDemo.PubSub},
      {Nx.Serving, serving: serving, name: SentenceTransformer},
      PhoenixDemo.Repo,
      PhoenixDemo.Endpoint
    ],
    strategy: :one_for_one
  )

defmodule PhoenixDemo.Repo.Migrations.CreateEverything do
  use Ecto.Migration

  def up do
    execute "CREATE EXTENSION IF NOT EXISTS vector"

    create table(:threads) do
      add :title, :string, null: false

      timestamps()
    end

    create table(:users) do
      add :name, :string, null: false

      timestamps()
    end

    create table(:messages) do
      add :text, :text, null: false
      add :embedding, :vector, size: 768

      add :thread_id, references(:threads), null: false
      add :user_id, references(:users), null: false

      timestamps()
    end

    create index("messages", ["embedding vector_ip_ops"], using: :hnsw)
  end

  def down do
    execute "DROP EXTENSION vector"
  end
end

case :file.read_file_info("priv") do
  {:ok, _} ->
    :ok
  _ ->
    PhoenixDemo.Repo.__adapter__.storage_up(PhoenixDemo.Repo.config)
    Ecto.Migrator.run(PhoenixDemo.Repo, [{0, PhoenixDemo.Repo.Migrations.CreateEverything}], :up, all: true, log: false)
    Mix.Task.run("run", ["data.exs", "--no-mix-exs"])
end

path = Path.join(["priv", "static", "uploads"])
File.mkdir_p(path)

Process.sleep(:infinity)
