defmodule AwsExRay.AwsMetadata do

  @moduledoc """
  Collect AWS metadata to add to segments

  On ECS (including Fargate), the metadata comes from the task metadata
  endpoint v4, whose URI ECS puts in `ECS_CONTAINER_METADATA_URI_V4`.
  Otherwise we try the EC2 instance metadata service.
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
      %{"ecs" => _} ->
        Application.put_env(:aws_ex_ray, :aws_metadata, result)
      %{"ec2" => _} ->
        Application.put_env(:aws_ex_ray, :aws_metadata, result)
      {{%RuntimeError{message: "Instance Meta Error" <> _}, _}, _} ->
        # Failed to reach the instance metadata endpoint.
        # Most likely we're not running on an EC2 instance.
        :ok
      _ ->
        Logger.debug("Error during AWS metadata request: #{Exception.format_exit(result)}")
    end
    {:stop, :normal, state}
  end

  def request_aws_metadata() do
    case System.get_env("ECS_CONTAINER_METADATA_URI_V4") do
      uri when is_binary(uri) and uri != "" ->
        :erlang.exit(request_ecs_metadata(uri))
      _ ->
        :erlang.exit(request_ec2_metadata())
    end
  end

  defp request_ecs_metadata(uri) do
    # The task metadata endpoint takes no IMDSv2 token, and it isn't
    # possible to get one on Fargate
    config = ExAws.Config.new(:ec2, access_key_id: "", secret_access_key: "", security_token: "")
    container = :json.decode(ExAws.InstanceMeta.request(config, uri))
    task = :json.decode(ExAws.InstanceMeta.request(config, uri <> "/task"))
    ecs_metadata(container, task, hostname())
  rescue
    # Don't let it pass for "not running on EC2" in handle_info
    e in RuntimeError -> reraise "ECS metadata error: " <> e.message, __STACKTRACE__
  end

  defp request_ec2_metadata() do
    config = ExAws.Config.new(:ec2, require_imds_v2: true, access_key_id: "", secret_access_key: "", security_token: "")
    result = ExAws.InstanceMeta.request(config, "http://169.254.169.254/latest/dynamic/instance-identity/document")
    map = :json.decode(result)
    %{"ec2" => %{
         "instance_id" => Map.get(map, "instanceId"),
         "instance_size" => Map.get(map, "instanceType"),
         "ami_id" => Map.get(map, "imageId"),
         "availability_zone" => Map.get(map, "availabilityZone")}}
  end

  @doc """
  Build the `aws` field of a segment from the container and task
  responses of the ECS task metadata endpoint v4.
  """
  @spec ecs_metadata(container :: map, task :: map, hostname :: String.t) :: map
  def ecs_metadata(container, task, hostname) do
    task_arn = Map.get(task, "TaskARN")
    ecs =
      %{
        "container"     => hostname,
        "container_id"  => Map.get(container, "DockerId"),
        "container_arn" => Map.get(container, "ContainerARN"),
        "task_arn"      => task_arn,
        "task_family"   => Map.get(task, "Family"),
        "cluster_arn"   => cluster_arn(Map.get(task, "Cluster"), task_arn),
        "launch_type"   => downcase(Map.get(task, "LaunchType"))
      }
      |> reject_nil_values()

    case cloudwatch_logs(container, task_arn) do
      nil  -> %{"ecs" => ecs}
      logs -> %{"ecs" => ecs, "cloudwatch_logs" => [logs]}
    end
  end

  # On EC2, "Cluster" can be the short name of the cluster instead of its ARN
  defp cluster_arn("arn:" <> _ = arn, _task_arn), do: arn
  defp cluster_arn(name, task_arn) when is_binary(name) do
    case arn_prefix(task_arn) do
      {region, account} -> "arn:aws:ecs:#{region}:#{account}:cluster/#{name}"
      nil               -> name
    end
  end
  defp cluster_arn(_, _), do: nil

  defp cloudwatch_logs(%{"LogDriver" => "awslogs", "LogOptions" => %{"awslogs-group" => group}}, task_arn) do
    case arn_prefix(task_arn) do
      {region, account} ->
        %{"log_group" => group, "arn" => "arn:aws:logs:#{region}:#{account}:log-group:#{group}"}
      nil ->
        %{"log_group" => group}
    end
  end
  defp cloudwatch_logs(_, _), do: nil

  defp arn_prefix(arn) when is_binary(arn) do
    case String.split(arn, ":", parts: 6) do
      ["arn", _partition, _service, region, account, _resource] -> {region, account}
      _ -> nil
    end
  end
  defp arn_prefix(_), do: nil

  defp downcase(s) when is_binary(s), do: String.downcase(s)
  defp downcase(_), do: nil

  defp reject_nil_values(map) do
    map |> Enum.reject(fn {_, v} -> is_nil(v) end) |> Map.new()
  end

  defp hostname() do
    {:ok, name} = :inet.gethostname()
    List.to_string(name)
  end
end
