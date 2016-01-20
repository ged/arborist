# -*- encoding: utf-8 -*-
# stub: arborist 0.0.1.pre20160106113421 ruby lib

Gem::Specification.new do |s|
  s.name = "arborist"
  s.version = "0.0.1.pre20160106113421"

  s.required_rubygems_version = Gem::Requirement.new("> 1.3.1") if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib"]
  s.authors = ["Michael Granger", "Mahlon E. Smith"]
  s.date = "2016-01-06"
  s.description = "Arborist is a monitoring framework that follows the UNIX philosophy\nof small parts and loose coupling for stability, reliability, and\ncustomizability."
  s.email = ["ged@FaerieMUD.org", "mahlon@martini.nu"]
  s.executables = ["amanagerd", "amonitord", "aobserverd"]
  s.extra_rdoc_files = ["Events.md", "History.md", "Manifest.txt", "Monitors.md", "Nodes.md", "Observers.md", "Protocol.md", "README.md", "TODO.md", "Events.md", "History.md", "Monitors.md", "Nodes.md", "Observers.md", "Protocol.md", "README.md", "TODO.md"]
  s.files = [".document", ".simplecov", "ChangeLog", "Events.md", "History.md", "LICENSE", "Manifest.txt", "Monitors.md", "Nodes.md", "Observers.md", "Protocol.md", "README.md", "Rakefile", "TODO.md", "bin/amanagerd", "bin/amonitord", "bin/aobserverd", "lib/arborist.rb", "lib/arborist/client.rb", "lib/arborist/event.rb", "lib/arborist/event/node_acked.rb", "lib/arborist/event/node_delta.rb", "lib/arborist/event/node_matching.rb", "lib/arborist/event/node_update.rb", "lib/arborist/event/sys_reloaded.rb", "lib/arborist/exceptions.rb", "lib/arborist/manager.rb", "lib/arborist/manager/event_publisher.rb", "lib/arborist/manager/tree_api.rb", "lib/arborist/mixins.rb", "lib/arborist/monitor.rb", "lib/arborist/monitor/socket.rb", "lib/arborist/monitor_runner.rb", "lib/arborist/node.rb", "lib/arborist/node/host.rb", "lib/arborist/node/root.rb", "lib/arborist/node/service.rb", "lib/arborist/observer.rb", "lib/arborist/observer/action.rb", "lib/arborist/observer/summarize.rb", "lib/arborist/observer_runner.rb", "lib/arborist/subscription.rb", "spec/arborist/client_spec.rb", "spec/arborist/event/node_update_spec.rb", "spec/arborist/event_spec.rb", "spec/arborist/manager/event_publisher_spec.rb", "spec/arborist/manager/tree_api_spec.rb", "spec/arborist/manager_spec.rb", "spec/arborist/mixins_spec.rb", "spec/arborist/monitor/socket_spec.rb", "spec/arborist/monitor_runner_spec.rb", "spec/arborist/monitor_spec.rb", "spec/arborist/node/host_spec.rb", "spec/arborist/node/root_spec.rb", "spec/arborist/node/service_spec.rb", "spec/arborist/node_spec.rb", "spec/arborist/observer/action_spec.rb", "spec/arborist/observer/summarize_spec.rb", "spec/arborist/observer_spec.rb", "spec/arborist/subscription_spec.rb", "spec/arborist_spec.rb", "spec/data/monitors/pings.rb", "spec/data/monitors/port_checks.rb", "spec/data/monitors/system_resources.rb", "spec/data/monitors/web_services.rb", "spec/data/nodes/duir.rb", "spec/data/nodes/localhost.rb", "spec/data/nodes/sidonie.rb", "spec/data/nodes/yevaud.rb", "spec/data/observers/auditor.rb", "spec/data/observers/webservices.rb", "spec/spec_helper.rb"]
  s.homepage = "http://deveiate.org/projects/arborist"
  s.licenses = ["BSD-3-Clause"]
  s.rdoc_options = ["--main", "README.md"]
  s.required_ruby_version = Gem::Requirement.new(">= 2.2.0")
  s.rubygems_version = "2.4.8"
  s.summary = "Arborist is a monitoring framework that follows the UNIX philosophy of small parts and loose coupling for stability, reliability, and customizability."

  if s.respond_to? :specification_version then
    s.specification_version = 4

    if Gem::Version.new(Gem::VERSION) >= Gem::Version.new('1.2.0') then
      s.add_runtime_dependency(%q<schedulability>, ["~> 0.1"])
      s.add_runtime_dependency(%q<loggability>, ["~> 0.11"])
      s.add_runtime_dependency(%q<configurability>, ["~> 2.2"])
      s.add_runtime_dependency(%q<pluggability>, ["~> 0.4"])
      s.add_runtime_dependency(%q<state_machines>, ["~> 0.2"])
      s.add_runtime_dependency(%q<msgpack>, ["~> 0.6"])
      s.add_runtime_dependency(%q<rbczmq>, ["~> 1.7"])
      s.add_development_dependency(%q<hoe-mercurial>, ["~> 1.4"])
      s.add_development_dependency(%q<hoe-deveiate>, ["~> 0.7"])
      s.add_development_dependency(%q<hoe-highline>, ["~> 0.2"])
      s.add_development_dependency(%q<rdoc>, ["~> 4.0"])
      s.add_development_dependency(%q<rspec>, ["~> 3.2"])
      s.add_development_dependency(%q<simplecov>, ["~> 0.9"])
      s.add_development_dependency(%q<timecop>, ["~> 0.7"])
      s.add_development_dependency(%q<hoe>, ["~> 3.14"])
    else
      s.add_dependency(%q<schedulability>, ["~> 0.1"])
      s.add_dependency(%q<loggability>, ["~> 0.11"])
      s.add_dependency(%q<configurability>, ["~> 2.2"])
      s.add_dependency(%q<pluggability>, ["~> 0.4"])
      s.add_dependency(%q<state_machines>, ["~> 0.2"])
      s.add_dependency(%q<msgpack>, ["~> 0.6"])
      s.add_dependency(%q<rbczmq>, ["~> 1.7"])
      s.add_dependency(%q<hoe-mercurial>, ["~> 1.4"])
      s.add_dependency(%q<hoe-deveiate>, ["~> 0.7"])
      s.add_dependency(%q<hoe-highline>, ["~> 0.2"])
      s.add_dependency(%q<rdoc>, ["~> 4.0"])
      s.add_dependency(%q<rspec>, ["~> 3.2"])
      s.add_dependency(%q<simplecov>, ["~> 0.9"])
      s.add_dependency(%q<timecop>, ["~> 0.7"])
      s.add_dependency(%q<hoe>, ["~> 3.14"])
    end
  else
    s.add_dependency(%q<schedulability>, ["~> 0.1"])
    s.add_dependency(%q<loggability>, ["~> 0.11"])
    s.add_dependency(%q<configurability>, ["~> 2.2"])
    s.add_dependency(%q<pluggability>, ["~> 0.4"])
    s.add_dependency(%q<state_machines>, ["~> 0.2"])
    s.add_dependency(%q<msgpack>, ["~> 0.6"])
    s.add_dependency(%q<rbczmq>, ["~> 1.7"])
    s.add_dependency(%q<hoe-mercurial>, ["~> 1.4"])
    s.add_dependency(%q<hoe-deveiate>, ["~> 0.7"])
    s.add_dependency(%q<hoe-highline>, ["~> 0.2"])
    s.add_dependency(%q<rdoc>, ["~> 4.0"])
    s.add_dependency(%q<rspec>, ["~> 3.2"])
    s.add_dependency(%q<simplecov>, ["~> 0.9"])
    s.add_dependency(%q<timecop>, ["~> 0.7"])
    s.add_dependency(%q<hoe>, ["~> 3.14"])
  end
end
