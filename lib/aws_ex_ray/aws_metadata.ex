defmodule AwsExRay.AwsMetadata do

  @moduledoc """
  Collect AWS metadata to add to segments
  """

  use GenServer, restart: :temporary
  require Logger

  def start_link(_) do
    GenServer.start_link(__MODULE__, {})
  end

  @impl true
  def init(_) do
    {_pid, ref} = Process.spawn(&request_aws_metadata/0, [:monitor])
    {:ok, %{ref: ref}}
  end

  @impl true
  def handle_info({:"DOWN", monitor_ref, :process, _, result}, state = %{ref: ref}) when ref === monitor_ref do
    case result do
      %{"ec2" => _} ->
        Application.put_env(:aws_ex_ray, :aws_metadata, result)
      _ ->
        Logger.debug("Error during instance identity request: #{Exception.format_exit(result)}")
    end
    {:stop, :normal, state}
  end

  def request_aws_metadata() do
    config = ExAws.Config.new(:ec2, require_imds_v2: true)
    result = ExAws.InstanceMeta.request(config, "http://169.254.169.254/latest/dynamic/instance-identity/document")
    map = Jason.decode!(result)
    :erlang.exit(%{"ec2" => %{
                      "instance_id" => Map.get(map, "instanceId"),
                      "instance_size" => Map.get(map, "instanceType"),
                      "ami_id" => Map.get(map, "imageId"),
                      "availability_zone" => Map.get(map, "availabilityZone")}})
  end
end
