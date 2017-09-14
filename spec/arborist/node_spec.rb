#!/usr/bin/env rspec -cfd

require_relative '../spec_helper'

require 'time'
require 'arborist/node'


describe Arborist::Node do

	before( :all ) do
		Arborist::Event.load_all
	end
	before( :each ) do
		@real_derivatives = described_class.derivatives.dup
	end
	after( :each ) do
		described_class.derivatives.replace( @real_derivatives )
	end


	let( :concrete_class ) do
		Class.new( described_class )
	end

	let( :identifier ) { 'the_identifier' }
	let( :identifier2 ) { 'the_other_identifier' }


	it "can be loaded from a file" do
		concrete_instance = nil
		expect( Kernel ).to receive( :load ).with( "a/path/to/a/node.rb" ) do
			concrete_instance = concrete_class.new( identifier )
		end

		result = described_class.load( "a/path/to/a/node.rb" )
		expect( result ).to be_an( Array )
		expect( result.length ).to eq( 1 )
		expect( result ).to include( concrete_instance )
	end


	it "can be constructed from a Hash" do
		instance = concrete_class.new( identifier,
			parent: 'branch',
			description: 'A testing node',
			tags: ['internal', 'testing']
		)

		expect( instance ).to be_a( described_class )
		expect( instance.parent ).to eq( 'branch' )
		expect( instance.description ).to eq( 'A testing node' )
		expect( instance.tags ).to include( 'internal', 'testing' )
	end


	it "can load multiple nodes from a single file" do
		concrete_instance1 = concrete_instance2 = nil
		expect( Kernel ).to receive( :load ).with( "a/path/to/a/node.rb" ) do
			concrete_instance1 = concrete_class.new( identifier )
			concrete_instance2 = concrete_class.new( identifier2 )
		end

		result = described_class.load( "a/path/to/a/node.rb" )
		expect( result ).to be_an( Array )
		expect( result.length ).to eq( 2 )
		expect( result ).to include( concrete_instance1, concrete_instance2 )
	end


	it "knows what its identifier is" do
		expect( described_class.new('good_identifier').identifier ).to eq( 'good_identifier' )
	end


	it "accepts identifiers with hyphens" do
		expect( described_class.new('router_nat-pmp').identifier ).to eq( 'router_nat-pmp' )
	end


	it "raises an error if the node identifier is invalid" do
		expect {
		   described_class.new 'bad identifier'
		}.to raise_error( RuntimeError, /identifier/i )
	end


	context "subnode classes" do

		it "can declare the type of node they live under" do
			subnode_class = Class.new( described_class )
			subnode_class.parent_type( concrete_class )

			expect( subnode_class.parent_types ).to include( concrete_class )
		end


		it "can be constructed via a factory method on instances of their parent type" do
			subnode_class = Class.new( described_class ) do
				def self::name; "TestSubNode"; end
				def self::plugin_name; "testsub"; end
			end
			described_class.derivatives['testsub'] = subnode_class

			subnode_class.parent_type( concrete_class )
			parent = concrete_class.new( 'branch' )
			node = parent.testsub( 'leaf' )

			expect( node ).to be_an_instance_of( subnode_class )
			expect( node.identifier ).to eq( 'leaf' )
			expect( node.parent ).to eq( 'branch' )
		end


		it "can pre-process the factory method arguments" do
			subnode_class = Class.new( described_class ) do
				def self::name; "TestSubNode"; end
				def self::plugin_name; "testsub"; end
				def args( new_args=nil )
					@args = new_args if new_args
					return @args
				end
				def modify( attributes )
					attributes = stringify_keys( attributes )
					super
					self.args( attributes['args'] )
				end
			end
			described_class.derivatives['testsub'] = subnode_class

			subnode_class.parent_type( concrete_class ) do |arg1, id, *args|
				[ id, {args: [arg1] + args} ]
			end

			parent = concrete_class.new( 'branch' )
			node = parent.testsub( :arg1, 'leaf', :arg2, :arg3 )

			expect( node ).to be_an_instance_of( subnode_class )
			expect( node.parent ).to eq( parent.identifier )
			expect( node.args ).to eq([ :arg1, :arg2, :arg3 ])
		end

	end


	context "an instance of a concrete subclass" do

		let( :node ) { concrete_class.new(identifier) }
		let( :child_node ) do
			concrete_class.new(identifier2) do
				parent 'the_identifier'
			end
		end


		it "can declare what its parent is by identifier" do
			expect( child_node.parent ).to eq( identifier )
		end


		it "can have child nodes added to it" do
			node.add_child( child_node )
			expect( node.children ).to include( child_node.identifier )
		end


		it "can have child nodes appended to it" do
			node << child_node
			expect( node.children ).to include( child_node.identifier )
		end


		it "raises an error if a node which specifies a different parent is added to it" do
			not_child_node = concrete_class.new(identifier2) do
				parent 'youre_not_my_mother'
			end
			expect {
				node.add_child( not_child_node )
			}.to raise_error( /not a child of/i )
		end


		it "doesn't add the same child more than once" do
			node.add_child( child_node )
			node.add_child( child_node )
			expect( node.children.size ).to eq( 1 )
		end


		it "knows it doesn't have any children if it's empty" do
			expect( node ).to_not have_children
		end


		it "knows it has children if subnodes have been added" do
			node.add_child( child_node )
			expect( node ).to have_children
		end


		it "knows how to remove one of its children" do
			node.add_child( child_node )
			node.remove_child( child_node )
			expect( node ).to_not have_children
		end

		describe "status" do

			it "starts out in `unknown` status" do
				expect( node ).to be_unknown
			end


			it "transitions to `up` status if its state is updated with no `error` property" do
				node.update( tested: true )
				expect( node ).to be_up
			end


			it "transitions to `down` status if its state is updated with an `error` property" do
				node.update( error: "Couldn't talk to it!" )
				expect( node ).to be_down
			end

			it "transitions from `down` to `acked` status if it's updated with an `ack` property" do
				node.status = 'down'
				node.errors = 'Something is wrong | he falls | betraying the trust | "\
					"there is a disaster in his life.'
				node.update( ack: {message: "Leitmotiv", sender: 'ged'}  )
				expect( node ).to be_acked
			end

			it "transitions from `acked` to `up` status if its error is cleared" do
				node.status = 'down'
				node.errors = { '_' => 'Something is wrong | he falls | betraying the trust | "\
					"there is a disaster in his life.' }
				node.update( ack: {message: "Leitmotiv", sender: 'ged'}  )
				node.update( error: nil )

				expect( node ).to be_up
			end

			it "stays `up` if its error is cleared and stays cleared" do
				node.status = 'down'
				node.errors = { '_' => 'stay up damn you!' }
				node.update( ack: {message: "Leitmotiv", sender: 'ged'}  )
				node.update( error: nil )
				node.update( error: nil )

				expect( node ).to be_up
			end

			it "transitions to `disabled` from `up` status if it's updated with an `ack` property" do
				node.status = 'up'
				node.update( ack: {message: "Maintenance", sender: 'mahlon'} )

				expect( node ).to be_disabled
			end

			it "transitions to `disabled` from `unknown` status if it's updated with an `ack` property" do
				node.status = 'unknown'
				node.update( ack: {message: "Maintenance", sender: 'mahlon'} )

				expect( node ).to be_disabled
			end

			it "stays `disabled` if it gets an error" do
				node.status = 'up'
				node.update( ack: {message: "Maintenance", sender: 'mahlon'} )
				node.update( error: "take me to the virus hospital" )

				expect( node ).to be_disabled
				expect( node.ack ).to_not be_nil
			end

			it "stays `disabled` if it gets a successful update" do
				node.status = 'up'
				node.update( ack: {message: "Maintenance", sender: 'mahlon'} )
				node.update( ping: {time: 0.02} )

				expect( node ).to be_disabled
				expect( node.ack ).to_not be_nil
			end

			it "transitions to `unknown` from `disabled` status if its ack is cleared" do
				node.status = 'up'
				node.update( ack: {message: "Maintenance", sender: 'mahlon'} )
				node.update( ack: nil )

				expect( node ).to_not be_disabled
				expect( node ).to be_unknown
				expect( node.ack ).to be_nil
			end

			it "knows if it's status deems it 'reachable'" do
				node.update( error: nil )
				expect( node ).to be_reachable
				expect( node ).to_not be_unreachable
			end

			it "knows if it's status deems it 'unreachable'" do
				node.update( error: 'ded' )
				expect( node ).to be_unreachable
				expect( node ).to_not be_reachable
			end

			it "groups errors from separate monitor by their key" do
				expect( node ).to be_unknown

				node.update( _monitor_key: 'MonitorTron2000', error: 'ded' )
				node.update( _monitor_key: 'MonitorTron5000', error: 'moar ded' )
				expect( node ).to be_down

				expect( node.errors.length ).to eq( 2 )
				node.update( _monitor_key: 'MonitorTron5000' )

				expect( node ).to be_down
				expect( node.errors.length ).to eq( 1 )

				node.update( _monitor_key: 'MonitorTron2000' )
				expect( node ).to be_up
			end

			it "sets a default monitor key" do
				node.update( error: 'ded' )
				expect( node ).to be_down
				expect( node.errors ).to eq({ '_' => 'ded' })
			end
		end


		describe "Properties API" do

			it "is initialized with an empty set" do
				expect( node.properties ).to be_empty
			end

			it "can attach arbitrary values to the node" do
				node.update( 'cider' => 'tasty' )
				expect( node.properties['cider'] ).to eq( 'tasty' )
			end

			it "replaces existing values on update" do
				node.properties.replace({
					'cider' => 'tasty',
					'cider_size' => '16oz',
				})
				node.update( 'cider_size' => '8oz' )

				expect( node.properties ).to include(
					'cider' => 'tasty',
					'cider_size' => '8oz'
				)
			end

			it "replaces nested values on update" do
				node.properties.replace({
					'cider' => {
						'description' => 'tasty',
						'size' => '16oz',
					},
					'sausage' => {
						'description' => 'pork',
						'size' => 'huge',
					},
					'music' => '80s'
				})
				node.update(
					'cider' => {'size' => '8oz'},
					'sausage' => 'Linguiça',
					'music' => {
						'genre' => '80s',
						'artist' => 'The Smiths'
					}
				)

				expect( node.properties ).to eq(
					'cider' => {
						'description' => 'tasty',
						'size' => '8oz',
					},
					'sausage' => 'Linguiça',
					'music' => {
						'genre' => '80s',
						'artist' => 'The Smiths'
					}
				)
			end

			it "removes pairs whose value is nil" do
				node.properties.replace({
					'cider' => {
						'description' => 'tasty',
						'size' => '16oz',
					},
					'sausage' => {
						'description' => 'pork',
						'size' => 'huge',
					},
					'music' => '80s'
				})
				node.update(
					'cider' => {'size' => nil},
					'sausage' => nil,
					'music' => {
						'genre' => '80s',
						'artist' => 'The Smiths'
					}
				)

				expect( node.properties ).to eq(
					'cider' => {
						'description' => 'tasty',
					},
					'music' => {
						'genre' => '80s',
						'artist' => 'The Smiths'
					}
				)
			end
		end


		describe "Enumeration" do

			it "iterates over its children for #each" do
				parent = node
				parent <<
					concrete_class.new('child1') { parent 'the_identifier' } <<
					concrete_class.new('child2') { parent 'the_identifier' } <<
					concrete_class.new('child3') { parent 'the_identifier' }

				expect( parent.map(&:identifier) ).to eq([ 'child1', 'child2', 'child3' ])
			end

		end


		describe "Serialization" do

			# From spec_helper.rb
			let( :concrete_class ) { TestNode }
			let( :node ) do
				concrete_class.new( 'foo' ) do
					parent 'bar'
					description "The prototypical node"
					tags :chunker, :hunky, :flippin, :hippo

					depends_on(
						all_of('postgres', 'rabbitmq', 'memcached', on: 'svchost'),
						any_of('webproxy', on: ['fe-host1','fe-host2','fe-host3'])
					)

					config os: 'freebsd-10'

					update( 'song' => 'Around the World', 'artist' => 'Daft Punk', 'length' => '7:09' )
				end
			end

			let( :tree ) do
				node_hierarchy( node,
					node_hierarchy( 'host-a',
						testing_node( 'host-a-www' ),
						testing_node( 'host-a-smtp' ),
						testing_node( 'host-a-imap' )
					),
					node_hierarchy( 'host-b',
						testing_node( 'host-b-www' ),
						testing_node( 'host-b-nfs' ),
						testing_node( 'host-b-ssh' )
					),
					node_hierarchy( 'host-c',
						testing_node( 'host-c-www' )
					),
					node_hierarchy( 'host-d',
						testing_node( 'host-d-ssh' ),
						testing_node( 'host-d-amqp' ),
						testing_node( 'host-d-database' ),
						testing_node( 'host-d-memcached' )
					)
				)
			end


			it "can restore saved state from an older copy of the node" do
				old_node = Marshal.load( Marshal.dump(node) )

				old_node.status = 'down'
				old_node.status_changed = Time.now - 400
				old_node.errors = "Host unreachable"
				old_node.update(
					ack: {
						'time' => Time.now - 200,
						'message' => "Technician dispatched.",
						'sender' => 'darby@example.com'
					}
				)
				old_node.properties.replace(
					'ping' => {
						'ttl' => 0.23
					}
				)
				old_node.last_contacted = Time.now - 28
				old_node.dependencies.mark_down( 'svchost-postgres' )

				node.restore( old_node )

				expect( node.status ).to eq( old_node.status )
				expect( node.status_changed ).to eq( old_node.status_changed )
				expect( node.errors ).to eq( old_node.errors )
				expect( node.ack ).to eq( old_node.ack )
				expect( node.properties ).to include( old_node.properties )
				expect( node.last_contacted ).to eq( old_node.last_contacted )
				expect( node.dependencies ).to eql( old_node.dependencies )
			end


			it "doesn't restore operational attributes from the node file on disk with those from saved state" do
				old_node = Marshal.load( Marshal.dump(node) )
				node_copy = Marshal.load( Marshal.dump(node) )

				old_node.instance_variable_set( :@parent, 'foo' )
				old_node.instance_variable_set( :@description, 'Some older description' )
				old_node.instance_variable_set( :@config, {'os' => 'freebsd-8'} )
				old_node.tags( :bunker, :lucky, :tickle, :trucker )
				old_node.source = '/somewhere/else'

				node.restore( old_node )

				expect( node.parent ).to eq( node_copy.parent )
				expect( node.description ).to eq( node_copy.description )
				expect( node.tags ).to eq( node_copy.tags )
				expect( node.source ).to eq( node_copy.source )
				expect( node.dependencies ).to eq( node_copy.dependencies )
				expect( node.config ).to eq( node_copy.config )
			end


			it "doesn't replace dependencies if they've changed" do
				old_node = Marshal.load( Marshal.dump(node) )
				old_node.dependencies.mark_down( 'svchost-postgres' )
				old_node.dependencies.mark_down( 'svchost-rabbitmq' )

				# Drop 'svchost-rabbitmq'
				node.depends_on(
					node.all_of('postgres', 'memcached', on: 'svchost'),
					node.any_of('webproxy', on: ['fe-host1','fe-host2','fe-host3'])
				)

				node.restore( old_node )

				expect( node.dependencies ).to_not eql( old_node.dependencies )
				expect( node.dependencies.all_identifiers ).to_not include( 'svchost-rabbitmq' )
				expect( node.dependencies.down_subdeps.length ).to eq( 1 )
			end


			it "can return a Hash of serializable node data" do
				result = tree.to_h

				expect( result ).to be_a( Hash )
				expect( result ).to include(
					:identifier,
					:parent, :description, :tags, :properties, :ack, :status,
					:last_contacted, :status_changed, :errors, :quieted_reasons,
					:dependencies
				)
				expect( result[:identifier] ).to eq( 'foo' )
				expect( result[:type] ).to eq( 'testnode' )
				expect( result[:parent] ).to eq( 'bar' )
				expect( result[:description] ).to eq( node.description )
				expect( result[:tags] ).to eq( node.tags )
				expect( result[:properties] ).to eq( node.properties )
				expect( result[:ack] ).to be_nil
				expect( result[:last_contacted] ).to eq( node.last_contacted.iso8601 )
				expect( result[:status_changed] ).to eq( node.status_changed.iso8601 )
				expect( result[:errors] ).to be_a( Hash )
				expect( result[:errors] ).to be_empty
				expect( result[:dependencies] ).to be_a( Hash )
				expect( result[:quieted_reasons] ).to be_a( Hash )

				expect( result[:children] ).to be_empty
			end


			it "can include all of its serialized children" do
				result = tree.to_h( depth: -1 )

				expect( result ).to be_a( Hash )
				expect( result ).to include(
					:identifier,
					:parent, :description, :tags, :properties, :ack, :status,
					:last_contacted, :status_changed, :errors, :quieted_reasons,
					:dependencies
				)

				expect( result[:children] ).to be_a( Hash )
				expect( result[:children].length ).to eq( 4 )

				host_a = result[:children]['host-a']
				expect( host_a ).to be_a( Hash )
				expect( host_a ).to include(
					:identifier,
					:parent, :description, :tags, :properties, :ack, :status,
					:last_contacted, :status_changed, :errors, :quieted_reasons,
					:dependencies
				)
				expect( host_a[:children].length ).to eq( 3 )
			end


			it "can include a specific depth of its children"


			it "can be reconstituted from a serialized Hash of node data" do
				hash = node.to_h
				cloned_node = concrete_class.from_hash( hash )

				expect( cloned_node ).to eq( node )
			end


			it "can be marshalled" do
				data = Marshal.dump( node )
				cloned_node = Marshal.load( data )

				expect( cloned_node ).to eq( node )
			end


			it "an ACKed node stays ACKed when serialized and restored" do
				node.update( error: "there's a fire" )
				node.update( ack: {
					message: 'We know about the fire. It rages on.',
					sender: '1986 Labyrinth David Bowie'
				})
				expect( node ).to be_acked

				restored_node = Marshal.load( Marshal.dump(node) )

				expect( restored_node ).to be_acked
			end


		end

	end


	describe "event system" do

		let( :node ) do
			concrete_class.new( 'foo' ) do
				parent 'bar'
				description "The prototypical node"
				tags :chunker, :hunky, :flippin, :hippo

				update(
					'song' => 'Around the World',
					'artist' => 'Daft Punk',
					'length' => '7:09',
					'cider' => {
						'description' => 'tasty',
						'size' => '16oz',
					},
					'sausage' => {
						'description' => 'pork',
						'size' => 'monsterous',
						'price' => {
							'units' => 1200,
							'currency' => 'usd'
						}
					},
					'music' => '80s'
				)
			end
		end


		it "generates a node.update event on update" do
			events = node.update( 'song' => "Around the World" )

			expect( events ).to be_an( Array )
			expect( events ).to all( be_a(Arborist::Event) )
			expect( events.size ).to eq( 1 )
			expect( events.first.type ).to eq( 'node.update' )
			expect( events.first.node ).to be( node )
		end


		it "generates a node.delta event when an update changes a value" do
			events = node.update(
				'song' => "Motherboard",
				'artist' => 'Daft Punk',
				'sausage' => {
					'price' => {
						'currency' => 'eur'
					}
				}
			)

			expect( events ).to be_an( Array )
			expect( events ).to all( be_a(Arborist::Event) )
			expect( events.size ).to eq( 2 )

			delta_event = events.find {|ev| ev.type == 'node.delta' }

			expect( delta_event.node ).to be( node )
			expect( delta_event.payload ).to eq({
				'song' => ['Around the World' , 'Motherboard'],
				'sausage' => {
					'price' => {
						'currency' => ['usd', 'eur']
					}
				}
			})
		end


		it "includes status changes in delta events" do
			events = node.update( error: "Couldn't talk to it!" )
			delta_event = events.find {|ev| ev.type == 'node.delta' }

			expect( delta_event.payload ).to include( 'status' => ['up', 'down'] )
		end


		it "generates a node.acked event when a node is acked" do
			node.update( error: 'ping failed ')
			events = node.update(ack: {
				message: "I have a poisonous friend. She's living in the house.",
				sender: 'Seabound'
			})

			expect( events.size ).to eq( 3 )
			ack_event = events.find {|ev| ev.type == 'node.acked' }

			expect( ack_event ).to be_a( Arborist::Event )
			expect( ack_event.payload ).to include( ack: a_hash_including(sender: 'Seabound') )
		end

	end


	describe "subscriptions" do

		let( :node ) do
			concrete_class.new( 'foo' ) do
				parent 'bar'
				description "The prototypical node"
				tags :chunker, :hunky, :flippin, :hippo
			end
		end



		it "allows the addition of a Subscription" do
			sub = Arborist::Subscription.new {}
			node.add_subscription( sub )
			expect( node.subscriptions ).to include( sub.id )
			expect( node.subscriptions[sub.id] ).to be( sub )
		end

		it "allows the removal of a Subscription" do
			sub = Arborist::Subscription.new {}
			node.add_subscription( sub )
			node.remove_subscription( sub.id )
			expect( node.subscriptions ).to_not include( sub )
		end


		it "can find subscriptions that match a given event" do
			events = node.update( 'song' => 'Fear', 'artist' => "Mind.in.a.Box" )
			delta_event = events.find {|ev| ev.type == 'node.delta' }

			sub = Arborist::Subscription.new( 'node.delta' ) {}
			node.add_subscription( sub )

			results = node.find_matching_subscriptions( delta_event )

			expect( results.size ).to eq( 1 )
			expect( results ).to all( be_a(Arborist::Subscription) )
			expect( results.first ).to be( sub )
		end


		it "can return the identifiers of all other nodes that subscribe to it" do
			
		end

	end


	describe "matching" do

		let( :concrete_class ) do
			cls = Class.new( described_class ) do
				def self::name; "TestNode"; end
			end
		end


		let( :node ) do
			concrete_class.new( 'foo' ) do
				parent 'bar'
				description "The prototypical node"
				tags :chunker, :hunky, :flippin, :hippo
				config os: 'freebsd-10'

				update(
					'song' => 'Around the World',
					'artist' => 'Daft Punk',
					'length' => '7:09',
					'cider' => {
						'description' => 'tasty',
						'size' => '16oz',
					},
					'sausage' => {
						'description' => 'pork',
						'size' => 'monsterous',
						'price' => {
							'units' => 1200,
							'currency' => 'usd'
						}
					},
					'music' => '80s'
				)
			end
		end


		it "can be matched with its status" do
			expect( node ).to match_criteria( status: 'up' )
			expect( node ).to_not match_criteria( status: 'down' )
		end


		it "can be matched with its type" do
			expect( node ).to match_criteria( type: 'testnode' )
			expect( node ).to_not match_criteria( type: 'service' )
		end


		it "can be matched with its parent" do
			expect( node ).to match_criteria( parent: 'bar' )
			expect( node ).to_not match_criteria( parent: 'hooowat' )
		end


		it "can be matched with a single tag" do
			expect( node ).to match_criteria( tag: 'hunky' )
			expect( node ).to_not match_criteria( tag: 'plucky' )
		end


		it "can be matched with multiple tags" do
			expect( node ).to match_criteria( tags: ['hunky', 'hippo'] )
			expect( node ).to_not match_criteria( tags: ['hunky', 'hippo', 'haggis'] )
		end


		it "can be matched with its identifier" do
			expect( node ).to match_criteria( identifier: 'foo' )
			expect( node ).to_not match_criteria( identifier: 'bar' )
		end


		it "can be matched with config values" do
			expect( node ).to match_criteria( config: {os: 'freebsd-10'} )
			expect( node ).to_not match_criteria( config: {os: 'macosx-10.11.3'} )
		end


		it "can be matched with its user properties" do
			expect( node ).to match_criteria( song: 'Around the World' )
			expect( node ).to match_criteria( artist: 'Daft Punk' )
			expect( node ).to match_criteria(
				sausage: {size: 'monsterous', price: {currency: 'usd'}},
				cider: { description: 'tasty'}
			)

			expect( node ).to_not match_criteria( length: '8:01' )
			expect( node ).to_not match_criteria(
				sausage: {size: 'lunch', price: {currency: 'usd'}},
				cider: { description: 'tasty' }
			)
			expect( node ).to_not match_criteria( sausage: {size: 'lunch'} )
			expect( node ).to_not match_criteria( other: 'key' )
			expect( node ).to_not match_criteria( sausage: 'weißwürst' )
		end

	end


	describe "secondary dependencies" do

		let( :provider_node_parent ) do
			concrete_class.new( 'san' )
		end

		let( :provider_node ) do
			concrete_class.new( 'san-iscsi' ) do
				parent 'san'
			end
		end

		let( :node ) do
			concrete_class.new( 'appserver' ) do
				description "An appserver virtual machine"
			end
		end

		let( :manager ) do
			man = Arborist::Manager.new
			man.load_tree([ node, provider_node, provider_node_parent ])
			man
		end


		it "can be declared for a node" do
			node.depends_on( 'san-iscsi' )
			expect( node ).to have_dependencies
			expect( node.dependencies ).to include( 'san-iscsi' )
		end


		it "can't be declared for the root node" do
			expect {
				node.depends_on( '_' )
			}.to raise_exception( Arborist::ConfigError, /root node/i )
		end


		it "can't be declared for itself" do
			expect {
				node.depends_on( 'appserver' )
			}.to raise_exception( Arborist::ConfigError, /itself/i )
		end


		it "can't be declared for any of its ancestors" do
			provider_node.depends_on( 'san' )

			expect {
				provider_node.register_secondary_dependencies( manager )
			}.to raise_exception( Arborist::ConfigError, /ancestor/i )
		end


		it "can't be declared for any of its decendants" do
			provider_node_parent.depends_on( 'san-iscsi' )

			expect {
				provider_node_parent.register_secondary_dependencies( manager )
			}.to raise_exception( Arborist::ConfigError, /descendant/i )
		end


		it "can be declared with a simple identifier" do
			node.depends_on( 'san-iscsi' )

			expect {
				node.register_secondary_dependencies( manager )
			}.to_not raise_exception
		end


		it "can be declared on a service on a host"  do
			node.depends_on( 'iscsi', on: 'san' )
			expect( node ).to have_dependencies
			expect( node.dependencies.behavior ).to eq( :all )
			expect( node.dependencies.identifiers ).to include( 'san-iscsi' )
		end


		it "can be declared for all of a group of identifiers" do
			node.depends_on( 'iscsi', 'memcached', 'ldap', on: 'dmz' )
			expect( node ).to have_dependencies
			expect( node.dependencies.behavior ).to eq( :all )
			expect( node.dependencies.identifiers ).to include( 'dmz-iscsi', 'dmz-memcached', 'dmz-ldap' )
		end


		it "can be declared for any of a group of identifiers" do
			node.depends_on( node.any_of('memcached', on: %w[blade1 blade2 blade3]) )
			expect( node ).to have_dependencies
			expect( node.dependencies.behavior ).to eq( :all )
			expect( node.dependencies.subdeps.size ).to eq( 1 )
			subdep = node.dependencies.subdeps.first
			expect( subdep.behavior ).to eq( :any )
			expect( subdep.identifiers ).
				to include( 'blade1-memcached', 'blade2-memcached', 'blade3-memcached' )
		end


		it "cause the node to be quieted when the dependent node goes down" do
			node.depends_on( provider_node.identifier )
			node.register_secondary_dependencies( manager )

			events = provider_node.update( error: "fatal disk error: offlined" )
			provider_node.publish_events( *events )

			expect( node ).to be_quieted
			expect( node ).to have_downed_dependencies
			# :TODO: Quieted description?
		end


		it "broadcasts events generated by handled event transitions" do
			vmhost01 = concrete_class.new( 'vmhost01' )
			vm01 = concrete_class.new( 'vm01' ) do
				parent 'vmhost01'
			end
			memcache = described_class.new( 'memcache' ) do
				parent 'vm01'
			end

			mgr = Arborist::Manager.new
			mgr.load_tree([ vmhost01, vm01, memcache ])

			events = vmhost01.
				update( ack: {message: "Imma gonna f up yo' sash", sender: "GOD"} )
			vmhost01.publish_events( *events )

			expect( memcache ).to be_quieted
		end

	end


	describe "operational attribute modification" do


		let( :node ) do
			concrete_class.new( 'foo' ) do
				parent 'bar'
				description "The prototypical node"
				tags :chunker, :hunky, :flippin, :hippo
			end
		end


		it "can change its parent" do
			node.modify( parent: 'foo' )
			expect( node.parent ).to eq( 'foo' )
		end


		it "can change its description" do
			node.modify( description: 'A different node' )
			expect( node.description ).to eq( 'A different node' )
		end


		it "can change its tags" do
			node.modify( tags: %w[dew dairy daisy dilettante] )
			expect( node.tags ).to eq( %w[dew dairy daisy dilettante] )
		end


		it "arrayifies tags modifications" do
			node.modify( tags: 'single' )
			expect( node.tags ).to eq( %w[single] )
		end

	end

end

