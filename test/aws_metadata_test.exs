defmodule AwsExRay.Test.AwsMetadataTest do
  use ExUnit.Case, async: false

  alias AwsExRay.AwsMetadata
  alias AwsExRay.Segment
  alias AwsExRay.Segment.Formatter
  alias AwsExRay.Trace

  # Abridged responses of the ECS task metadata endpoint v4 on Fargate
  @container %{
    "DockerId" => "2dd3dc952ec14d6ab1346dfa97790232-0137164860",
    "Name" => "metrics-api",
    "ContainerARN" => "arn:aws:ecs:us-east-1:123456789012:container/metrics-api/2dd3dc952ec14d6ab1346dfa97790232/c7563696-5fab-4c6d-8a92-be0618948d62",
    "LogDriver" => "awslogs",
    "LogOptions" => %{
      "awslogs-group" => "/ecs/metrics-api",
      "awslogs-region" => "us-east-1",
      "awslogs-stream" => "ecs/metrics-api/2dd3dc952ec14d6ab1346dfa97790232"
    }
  }

  @task %{
    "Cluster" => "arn:aws:ecs:us-east-1:123456789012:cluster/metrics-api",
    "TaskARN" => "arn:aws:ecs:us-east-1:123456789012:task/metrics-api/2dd3dc952ec14d6ab1346dfa97790232",
    "Family" => "metrics-api",
    "Revision" => "7",
    "LaunchType" => "FARGATE"
  }

  test "ECS metadata on Fargate" do
    assert AwsMetadata.ecs_metadata(@container, @task, "ip-10-0-0-1.ec2.internal") == %{
      "ecs" => %{
        "container" => "ip-10-0-0-1.ec2.internal",
        "container_id" => "2dd3dc952ec14d6ab1346dfa97790232-0137164860",
        "container_arn" => @container["ContainerARN"],
        "task_arn" => @task["TaskARN"],
        "task_family" => "metrics-api",
        "cluster_arn" => "arn:aws:ecs:us-east-1:123456789012:cluster/metrics-api",
        "launch_type" => "fargate"
      },
      "cloudwatch_logs" => [
        %{
          "log_group" => "/ecs/metrics-api",
          "arn" => "arn:aws:logs:us-east-1:123456789012:log-group:/ecs/metrics-api"
        }
      ]
    }
  end

  test "ECS metadata with a cluster name and no awslogs" do
    container = Map.drop(@container, ["LogDriver", "LogOptions"])
    task = %{@task | "Cluster" => "metrics-api", "LaunchType" => "EC2"}
    metadata = AwsMetadata.ecs_metadata(container, task, "host")

    refute Map.has_key?(metadata, "cloudwatch_logs")
    assert metadata["ecs"]["cluster_arn"] == "arn:aws:ecs:us-east-1:123456789012:cluster/metrics-api"
    assert metadata["ecs"]["launch_type"] == "ec2"
  end

  test "origin of a segment" do
    fargate = AwsMetadata.ecs_metadata(@container, @task, "host")
    ecs_on_ec2 = AwsMetadata.ecs_metadata(@container, %{@task | "LaunchType" => "EC2"}, "host")
    ec2 = %{"ec2" => %{"instance_id" => "i-0123456789abcdef0"}}

    assert origin(fargate) == "AWS::ECS::Fargate"
    assert origin(ecs_on_ec2) == "AWS::ECS::Container"
    assert origin(ec2) == "AWS::EC2::Instance"
    assert origin(nil) == nil

    assert %{aws: ^fargate} = format(fargate)
  end

  defp format(aws) do
    %{Segment.new(Trace.new(%{}), "test") | aws: aws} |> Formatter.to_map()
  end

  defp origin(aws), do: Map.get(format(aws), :origin)
end
