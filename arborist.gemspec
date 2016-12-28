# -*- encoding: utf-8 -*-
# stub: arborist 0.0.1.pre20161228143930 ruby lib

Gem::Specification.new do |s|
  s.name = "arborist".freeze
  s.version = "0.0.1.pre20161228143930"

  s.required_rubygems_version = Gem::Requirement.new("> 1.3.1".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["Michael Granger".freeze, "Mahlon E. Smith".freeze]
  s.cert_chain = ["certs/ged.pem".freeze]
  s.date = "2016-12-28"
  s.description = "Arborist is a monitoring toolkit that follows the UNIX philosophy\nof small parts and loose coupling for stability, reliability, and\ncustomizability.\n\n[![Build Status](https://semaphoreci.com/api/v1/projects/13677b60-5f81-4e6e-a9c6-e21d30daa4ca/461532/badge.svg)](https://semaphoreci.com/ged/arborist)".freeze
  s.email = ["ged@FaerieMUD.org".freeze, "mahlon@martini.nu".freeze]
  s.executables = ["arborist".freeze]
  s.extra_rdoc_files = ["Events.md".freeze, "History.md".freeze, "Manifest.txt".freeze, "Monitors.md".freeze, "Nodes.md".freeze, "Observers.md".freeze, "Protocol.md".freeze, "README.md".freeze, "TODO.md".freeze, "Tutorial.md".freeze, "Events.md".freeze, "History.md".freeze, "Monitors.md".freeze, "Nodes.md".freeze, "Observers.md".freeze, "Protocol.md".freeze, "README.md".freeze, "TODO.md".freeze, "Tutorial.md".freeze]
  s.files = [".document".freeze, ".simplecov".freeze, "ChangeLog".freeze, "Events.md".freeze, "History.md".freeze, "Manifest.txt".freeze, "Monitors.md".freeze, "Nodes.md".freeze, "Observers.md".freeze, "Protocol.md".freeze, "README.md".freeze, "Rakefile".freeze, "TODO.md".freeze, "Tutorial.md".freeze, "bin/arborist".freeze, "lib/arborist.rb".freeze, "lib/arborist/cli.rb".freeze, "lib/arborist/client.rb".freeze, "lib/arborist/command/client.rb".freeze, "lib/arborist/command/config.rb".freeze, "lib/arborist/command/start.rb".freeze, "lib/arborist/command/watch.rb".freeze, "lib/arborist/dependency.rb".freeze, "lib/arborist/event.rb".freeze, "lib/arborist/event/node.rb".freeze, "lib/arborist/event/node_acked.rb".freeze, "lib/arborist/event/node_delta.rb".freeze, "lib/arborist/event/node_disabled.rb".freeze, "lib/arborist/event/node_down.rb".freeze, "lib/arborist/event/node_quieted.rb".freeze, "lib/arborist/event/node_unknown.rb".freeze, "lib/arborist/event/node_up.rb".freeze, "lib/arborist/event/node_update.rb".freeze, "lib/arborist/exceptions.rb".freeze, "lib/arborist/loader.rb".freeze, "lib/arborist/loader/file.rb".freeze, "lib/arborist/manager.rb".freeze, "lib/arborist/manager/event_publisher.rb".freeze, "lib/arborist/manager/tree_api.rb".freeze, "lib/arborist/mixins.rb".freeze, "lib/arborist/monitor.rb".freeze, "lib/arborist/monitor/socket.rb".freeze, "lib/arborist/monitor_runner.rb".freeze, "lib/arborist/node.rb".freeze, "lib/arborist/node/ack.rb".freeze, "lib/arborist/node/host.rb".freeze, "lib/arborist/node/resource.rb".freeze, "lib/arborist/node/root.rb".freeze, "lib/arborist/node/service.rb".freeze, "lib/arborist/observer.rb".freeze, "lib/arborist/observer/action.rb".freeze, "lib/arborist/observer/summarize.rb".freeze, "lib/arborist/observer_runner.rb".freeze, "lib/arborist/subscription.rb".freeze, "spec/arborist/client_spec.rb".freeze, "spec/arborist/dependency_spec.rb".freeze, "spec/arborist/event/node_delta_spec.rb".freeze, "spec/arborist/event/node_down_spec.rb".freeze, "spec/arborist/event/node_spec.rb".freeze, "spec/arborist/event/node_update_spec.rb".freeze, "spec/arborist/event_spec.rb".freeze, "spec/arborist/manager/event_publisher_spec.rb".freeze, "spec/arborist/manager/tree_api_spec.rb".freeze, "spec/arborist/manager_spec.rb".freeze, "spec/arborist/mixins_spec.rb".freeze, "spec/arborist/monitor/socket_spec.rb".freeze, "spec/arborist/monitor_runner_spec.rb".freeze, "spec/arborist/monitor_spec.rb".freeze, "spec/arborist/node/ack_spec.rb".freeze, "spec/arborist/node/host_spec.rb".freeze, "spec/arborist/node/resource_spec.rb".freeze, "spec/arborist/node/root_spec.rb".freeze, "spec/arborist/node/service_spec.rb".freeze, "spec/arborist/node_spec.rb".freeze, "spec/arborist/observer/action_spec.rb".freeze, "spec/arborist/observer/summarize_spec.rb".freeze, "spec/arborist/observer_runner_spec.rb".freeze, "spec/arborist/observer_spec.rb".freeze, "spec/arborist/subscription_spec.rb".freeze, "spec/arborist_spec.rb".freeze, "spec/data/monitors/pings.rb".freeze, "spec/data/monitors/port_checks.rb".freeze, "spec/data/monitors/system_resources.rb".freeze, "spec/data/monitors/web_services.rb".freeze, "spec/data/nodes/localhost.rb".freeze, "spec/data/nodes/sidonie.rb".freeze, "spec/data/nodes/sub/duir.rb".freeze, "spec/data/nodes/yevaud.rb".freeze, "spec/data/observers/auditor.rb".freeze, "spec/data/observers/webservices.rb".freeze, "spec/spec_helper.rb".freeze]
  s.homepage = "http://deveiate.org/projects/arborist".freeze
  s.licenses = ["BSD-3-Clause".freeze]
  s.rdoc_options = ["--main".freeze, "README.md".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 2.3.1".freeze)
  s.rubygems_version = "2.6.8".freeze
  s.summary = "Arborist is a monitoring toolkit that follows the UNIX philosophy of small parts and loose coupling for stability, reliability, and customizability".freeze

  if s.respond_to? :specification_version then
    s.specification_version = 4

    if Gem::Version.new(Gem::VERSION) >= Gem::Version.new('1.2.0') then
      s.add_runtime_dependency(%q<schedulability>.freeze, ["~> 0.1"])
      s.add_runtime_dependency(%q<loggability>.freeze, ["~> 0.12"])
      s.add_runtime_dependency(%q<configurability>.freeze, ["~> 3.0"])
      s.add_runtime_dependency(%q<pluggability>.freeze, ["~> 0.4"])
      s.add_runtime_dependency(%q<state_machines>.freeze, ["~> 0.2"])
      s.add_runtime_dependency(%q<msgpack>.freeze, ["~> 0.6"])
      s.add_runtime_dependency(%q<rbczmq>.freeze, ["~> 1.7"])
      s.add_runtime_dependency(%q<gli>.freeze, ["~> 2.3"])
      s.add_runtime_dependency(%q<highline>.freeze, ["~> 1.7"])
      s.add_development_dependency(%q<hoe-mercurial>.freeze, ["~> 1.4"])
      s.add_development_dependency(%q<hoe-deveiate>.freeze, ["~> 0.8"])
      s.add_development_dependency(%q<hoe-highline>.freeze, ["~> 0.2"])
      s.add_development_dependency(%q<rspec>.freeze, ["~> 3.2"])
      s.add_development_dependency(%q<simplecov>.freeze, ["~> 0.9"])
      s.add_development_dependency(%q<timecop>.freeze, ["~> 0.7"])
      s.add_development_dependency(%q<rdoc>.freeze, ["~> 4.0"])
      s.add_development_dependency(%q<hoe>.freeze, ["~> 3.15"])
    else
      s.add_dependency(%q<schedulability>.freeze, ["~> 0.1"])
      s.add_dependency(%q<loggability>.freeze, ["~> 0.12"])
      s.add_dependency(%q<configurability>.freeze, ["~> 3.0"])
      s.add_dependency(%q<pluggability>.freeze, ["~> 0.4"])
      s.add_dependency(%q<state_machines>.freeze, ["~> 0.2"])
      s.add_dependency(%q<msgpack>.freeze, ["~> 0.6"])
      s.add_dependency(%q<rbczmq>.freeze, ["~> 1.7"])
      s.add_dependency(%q<gli>.freeze, ["~> 2.3"])
      s.add_dependency(%q<highline>.freeze, ["~> 1.7"])
      s.add_dependency(%q<hoe-mercurial>.freeze, ["~> 1.4"])
      s.add_dependency(%q<hoe-deveiate>.freeze, ["~> 0.8"])
      s.add_dependency(%q<hoe-highline>.freeze, ["~> 0.2"])
      s.add_dependency(%q<rspec>.freeze, ["~> 3.2"])
      s.add_dependency(%q<simplecov>.freeze, ["~> 0.9"])
      s.add_dependency(%q<timecop>.freeze, ["~> 0.7"])
      s.add_dependency(%q<rdoc>.freeze, ["~> 4.0"])
      s.add_dependency(%q<hoe>.freeze, ["~> 3.15"])
    end
  else
    s.add_dependency(%q<schedulability>.freeze, ["~> 0.1"])
    s.add_dependency(%q<loggability>.freeze, ["~> 0.12"])
    s.add_dependency(%q<configurability>.freeze, ["~> 3.0"])
    s.add_dependency(%q<pluggability>.freeze, ["~> 0.4"])
    s.add_dependency(%q<state_machines>.freeze, ["~> 0.2"])
    s.add_dependency(%q<msgpack>.freeze, ["~> 0.6"])
    s.add_dependency(%q<rbczmq>.freeze, ["~> 1.7"])
    s.add_dependency(%q<gli>.freeze, ["~> 2.3"])
    s.add_dependency(%q<highline>.freeze, ["~> 1.7"])
    s.add_dependency(%q<hoe-mercurial>.freeze, ["~> 1.4"])
    s.add_dependency(%q<hoe-deveiate>.freeze, ["~> 0.8"])
    s.add_dependency(%q<hoe-highline>.freeze, ["~> 0.2"])
    s.add_dependency(%q<rspec>.freeze, ["~> 3.2"])
    s.add_dependency(%q<simplecov>.freeze, ["~> 0.9"])
    s.add_dependency(%q<timecop>.freeze, ["~> 0.7"])
    s.add_dependency(%q<rdoc>.freeze, ["~> 4.0"])
    s.add_dependency(%q<hoe>.freeze, ["~> 3.15"])
  end
end
