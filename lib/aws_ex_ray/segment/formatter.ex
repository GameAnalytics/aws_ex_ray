  defmodule AwsExRay.Segment.Formatter do

    @moduledoc ~S"""
    This module provides a formatter functions
    for segment record
    """

    alias AwsExRay.Segment
    alias AwsExRay.Record.Error
    alias AwsExRay.Record.HTTPRequest
    alias AwsExRay.Record.HTTPResponse

    def to_json(seg) do
      seg |> to_map() |> Poison.encode!()
    end

    def to_map(seg) do
      %{
        name:        seg.name,
        id:          seg.id,
        trace_id:    seg.trace.root,
        start_time:  seg.start_time,
        annotations: seg.annotation,
        metadata:    seg.metadata
      }
      |> embed_version(seg)
      |> embed_progress(seg)
      |> embed_parent(seg)
      |> embed_http(seg)
      |> embed_error(seg)
      |> embed_aws(seg)
      |> embed_user(seg)
    end

    defp embed_error(m, seg) do
      if seg.error == nil do
        m
      else
        error = Error.to_map(seg.error)
        Map.merge(m, error)
      end
    end

    defp embed_http(m, seg) do
      if seg.http.request == nil && seg.http.response == nil do
        m
      else
        http = %{}
             |> embed_http_request(seg)
             |> embed_http_response(seg)
        Map.put(m, :http, http)
      end
    end

    defp embed_http_request(http, seg) do
      if seg.http.request != nil do
        req = HTTPRequest.to_map(seg.http.request)
        Map.put(http, :request, req)
      else
        http
      end
    end

    defp embed_http_response(http, seg) do
      if seg.http.response != nil do
        res = HTTPResponse.to_map(seg.http.response)
        Map.put(http, :response, res)
      else
        http
      end
    end

    defp embed_parent(m, seg) do
      if seg.trace.parent != "" do
        Map.put(m, :parent_id, seg.trace.parent)
      else
        m
      end
    end

    defp embed_version(m, seg) do
      if seg.version != "" do
        Map.put(m, :service, %{version: seg.version})
      else
        m
      end
    end

    defp embed_progress(m, seg) do
      if Segment.finished?(seg) do
        Map.put(m, :end_time, seg.end_time)
      else
        Map.put(m, :in_progress, true)
      end
    end

    defp embed_aws(m, seg) do
      case seg.aws do
        nil ->
          m
        aws_metadata when is_map(aws_metadata) ->
          m = Map.put(m, :aws, aws_metadata)
          case origin(aws_metadata) do
            nil    -> m
            origin -> Map.put(m, :origin, origin)
          end
      end
    end

    defp origin(%{"ecs" => %{"launch_type" => "fargate"}}), do: "AWS::ECS::Fargate"
    defp origin(%{"ecs" => _}), do: "AWS::ECS::Container"
    defp origin(%{"ec2" => _}), do: "AWS::EC2::Instance"
    defp origin(_), do: nil

    defp embed_user(m, seg) do
      case seg.user do
        nil ->
          m
        user ->
          Map.put(m, :user, user)
      end
    end

  end
