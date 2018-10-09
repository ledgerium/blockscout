defmodule Explorer.Counters.TransactionCounter do
  use GenServer

  @moduledoc """
  Module responsible for fetching and consolidating the number of transactions by address.
  """

  alias Explorer.Chain
  alias Explorer.Chain.{Hash, Transaction}

  @table :transaction_counter

  def table_name do
    @table
  end

  @doc """
  Starts a process to continually monitor the transaction counters.
  """
  @spec start_link(term()) :: GenServer.on_start()
  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  ## Server
  @impl true
  def init(args) do
    create_table()

    Task.start_link(&consolidate/0)

    Chain.subscribe_to_events(:transactions)

    {:ok, args}
  end

  def create_table do
    opts = [
      :set,
      :named_table,
      :public,
      read_concurrency: true,
      write_concurrency: true
    ]

    :ets.new(table_name(), opts)
  end

  @doc """
  Consolidates the number of transactions grouped by address.
  """
  def consolidate do
    total_transactions = Transaction.consolidate_by_address()

    for {address_hash, total} <- total_transactions do
      insert_or_update_counter(address_hash, total)
    end
  end

  @doc """
  Fetches the number of transactions related to a address hash.
  """
  @spec fetch(Hash.t()) :: non_neg_integer
  def fetch(address_hash) do
    do_fetch(:ets.lookup(table_name(), to_string(address_hash)))
  end

  defp do_fetch([{_, result} | _]), do: result
  defp do_fetch([]), do: 0

  @impl true
  def handle_info({:chain_event, :transactions, _type, transaction_hashes}, state) do
    transaction_hashes
    |> find_transactions
    |> Enum.flat_map(&[&1.to_address_hash, &1.from_address_hash, &1.created_contract_address_hash])
    |> Enum.reject(&is_nil/1)
    |> Enum.each(&insert_or_update_counter(&1, 1))

    {:noreply, state}
  end

  defp find_transactions(transaction_hashes) do
    Chain.hashes_to_transactions(transaction_hashes, [])
  end

  @doc """
  Inserts a new item into the `:ets` table.

  When the record exist, the counter will be incremented by one. When the
  record does not exist, the counter will be inserted with a default value.
  """
  @spec insert_or_update_counter(Hash.t(), non_neg_integer) :: term()
  def insert_or_update_counter(address_hash, number) do
    default = {to_string(address_hash), 0}

    :ets.update_counter(table_name(), to_string(address_hash), number, default)
  end
end
