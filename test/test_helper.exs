Application.ensure_all_started(:mox)
AwsExRay.Client.Sandbox.start_link([])
AwsExRay.Store.MonitorSupervisor.start_link([])
ExUnit.start()
