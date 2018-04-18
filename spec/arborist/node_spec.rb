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


	shared_examples_for "a reachable node" do

		it "is still 'reachable'" do
			expect( node ).to be_reachable
			expect( node ).to_not be_unreachable
		end

	end


	shared_examples_for "an unreachable node" do

		it "is not 'reachable'" do
			expect( node ).to_not be_reachable
			expect( node ).to be_unreachable
		end

	end


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

		let( :parent_node ) { concrete_class.new(identifier) }
		let( :sibling_node ) do
			concrete_class.new( 'sibling' ) do
				parent 'the_identifier'
			end
		end
		let( :node ) do
			concrete_class.new( identifier2 ) do
				parent 'the_identifier'
			end
		end


		it "can declare what its parent is by identifier" do
			expect( node.parent ).to eq( identifier )
		end


		it "can have child nodes added to it" do
			parent_node.add_child( node )
			expect( parent_node.children ).to include( node.identifier )
		end


		it "can have child nodes appended to it" do
			parent_node << node
			expect( parent_node.children ).to include( node.identifier )
		end


		it "raises an error if a node which specifies a different parent is added to it" do
			stranger_node = concrete_class.new( identifier2 ) do
				parent 'youre_not_my_mother'
			end
			expect {
				parent_node.add_child( stranger_node )
			}.to raise_error( /not a child of/i )
		end


		it "doesn't add the same child more than once" do
			parent_node.add_child( node )
			parent_node.add_child( node )
			expect( parent_node.children.size ).to eq( 1 )
		end


		it "knows it doesn't have any children if it's empty" do
			expect( parent_node ).to_not have_children
		end


		it "knows it has children if subnodes have been added" do
			parent_node.add_child( node )
			expect( parent_node ).to have_children
		end


		it "knows how to remove one of its children" do
			parent_node.add_child( node )
			parent_node.remove_child( node )
			expect( parent_node ).to_not have_children
		end


		it "starts out in `unknown` status" do
			expect( parent_node ).to be_unknown
		end


		it "remembers status time changes" do
			expect( node.status_changed ).to eq( Time.at(0) )

			time = Time.at( 1523900910 )
			allow( Time ).to receive( :now ).and_return( time )

			node.update( { error: 'boom' } )
			expect( node ).to be_down
			expect( node.status_changed ).to eq( time )
			expect( node.status_last_changed ).to eq( Time.at(0) )


			node.update( {} )
			expect( node ).to be_up
			expect( node.status_last_changed ).to eq( time )
		end


		it "groups errors from separate monitors by their key" do
			expect( node ).to be_unknown

			node.update( {error: 'ded'}, 'MonitorTron2000' )
			node.update( {error: 'moar ded'}, 'MonitorTron5000' )
			expect( node ).to be_down

			expect( node.errors.length ).to eq( 2 )
			node.update( {}, 'MonitorTron5000' )

			expect( node ).to be_down
			expect( node.errors.length ).to eq( 1 )

			node.update( {}, 'MonitorTron2000' )
			expect( node ).to be_up
		end


		it "sets a default monitor key" do
			node.update( error: 'ded' )
			expect( node ).to be_down
			expect( node.errors ).to eq({ '_' => 'ded' })
		end


		describe "in `unknown` status" do

			let( :node ) do
				obj = super()
				obj.status = 'unknown'
				obj
			end


			it_behaves_like "a reachable node"


			it "transitions to `up` status if doesn't have any errors after an update" do
				expect {
					node.update( tested: true )
				}.to change { node.status }.from( 'unknown' ).to( 'up' )
			end


			it "transitions to `down` status if its state is updated with an `error` property" do
				expect {
					node.update( error: "Couldn't talk to it!" )
				}.to change { node.status }.from( 'unknown' ).to( 'down' )
			end


			it "transitions to `warn` status if its state is updated with a `warning` property" do
				expect {
					node.update( warning: "Things are starting to look bad!" )
				}.to change { node.status }.from( 'unknown' ).to( 'warn' )
			end


			it "transitions to `disabled` if it's acknowledged" do
				expect {
					node.acknowledge( message: "Maintenance", sender: 'mahlon' )
				}.to change { node.status }.from( 'unknown' ).to( 'disabled' )
			end

		end


		describe "in `up` status" do

			let( :node ) do
				obj = super()
				obj.status = 'up'
				obj
			end


			it_behaves_like "a reachable node"


			it "stays in `up` status if doesn't have any errors after an update" do
				expect {
					node.update( tested: true )
				}.to_not change { node.status }.from( 'up' )
			end


			it "transitions to `down` status if its state is updated with an `error` property" do
				expect {
					node.update( error: "Couldn't talk to it!" )
				}.to change { node.status }.from( 'up' ).to( 'down' )
			end


			it "transitions to `down` status if it's updated with both an `error` and `warning` property" do
				expect {
					node.update( error: "Couldn't talk to it!", warning: "Above configured levels!" )
				}.to change { node.status }.from( 'up' ).to( 'down' )
			end


			it "transitions to `warn` status if its state is updated with a `warning` property" do
				expect {
					node.update( warning: "Things are starting to look bad!" )
				}.to change { node.status }.from( 'up' ).to( 'warn' )
			end


			it "transitions to `disabled` if it's acknowledged" do
				expect {
					node.acknowledge( message: "Maintenance", sender: 'mahlon' )
				}.to change { node.status }.from( 'up' ).to( 'disabled' )
			end


			it "transitions to `quieted` if it's notified that its parent has gone down" do
				down_event = Arborist::Event.create( :node_down, parent_node )
				expect {
					node.handle_event( down_event )
				}.to change { node.status }.from( 'up' ).to( 'quieted' )
			end

		end


		describe "in `down` status" do

			let( :node ) do
				obj = super()
				obj.status = 'down'
				obj.errors['moldovia'] = 'Something is wrong | he falls | betraying the trust | "\
					"there is a disaster in his life.'
				obj
			end


			it_behaves_like "an unreachable node"


			it "transitions to `acked` status if it's acknowledged" do
				expect {
					node.acknowledge( message: "Leitmotiv", sender: 'ged' )
				}.to change { node.status }.from( 'down' ).to( 'acked' )
			end


			it "transitions to `up` status if all of its errors are cleared" do
				expect {
					node.update( {error: nil}, 'moldovia' )
				}.to change { node.status }.from( 'down' ).to( 'up' )
			end

		end


		describe "in `warn` status" do

			let( :node ) do
				obj = super()
				obj.status = 'warn'
				obj.warnings = { 'beach' => 'Sweaty but functional servers.' }
				obj
			end


			it_behaves_like "a reachable node"


			it "transitions to `up` if its warnings are cleared" do
				expect {
					node.update( {warning: nil}, 'beach' )
				}.to change { node.status }.from( 'warn' ).to( 'up' )
			end


			it "transitions to `down` if has an error set" do
				expect {
					node.update( {error: "Shark warning."}, 'beach' )
				}.to change { node.status }.from( 'warn' ).to( 'down' )
			end


			it "transitions to `disabled` if it's acknowledged" do
				expect {
					node.acknowledge( message: "Chill", sender: 'ged' )
				}.to change { node.status }.from( 'warn' ).to( 'disabled' )
			end

		end


		describe "in `acked` status" do

			let( :node ) do
				obj = super()
				obj.status = 'acked'
				obj.errors['moldovia'] = 'Something is wrong | he falls | betraying the trust | "\
					"there is a disaster in his life.'
				obj.acknowledge( message: "Leitmotiv", sender: 'ged' )
				obj
			end


			it_behaves_like "a reachable node"


			it "transitions to `up` status if its error is cleared" do
				expect {
					node.update( {error: nil}, 'moldovia' )
				}.to change { node.status }.from( 'acked' ).to( 'up' )
			end


			it "stays `up` if it is updated twice with an error key" do
				node.update( {error: nil}, 'moldovia' )

				expect {
					node.update( {error: nil}, 'moldovia' ) # make sure it stays cleared
				}.to_not change { node.status }.from( 'up' )
			end

		end


		describe "in `disabled` status" do

			let( :node ) do
				obj = super()
				obj.acknowledge( message: "Bikini models", sender: 'ged' )
				obj
			end


			it_behaves_like "an unreachable node"


			it "stays `disabled` if it gets an error" do
				expect {
					node.update( error: "take me to the virus hospital" )
				}.to_not change { node.status }.from( 'disabled' )

				expect( node.ack ).to_not be_nil
			end


			it "stays `disabled` if it gets a warning" do
				expect {
					node.update( warning: "heartbone" )
				}.to_not change { node.status }.from( 'disabled' )

				expect( node.ack ).to_not be_nil
			end


			it "stays `disabled` if it gets a successful update" do
				expect {
					node.update( ping: {time: 0.02} )
				}.to_not change { node.status }.from( 'disabled' )

				expect( node.ack ).to_not be_nil
			end


			it "transitions to `unknown` if its acknowledgment is cleared" do
				expect {
					node.unacknowledge
				}.to change { node.status }.from( 'disabled' ).to( 'unknown' )

				expect( node.ack ).to be_nil
			end

		end


		describe "in `quieted` status because its parent is down" do

			let( :down_event ) { Arborist::Event.create(:node_down, parent_node) }
			let( :up_event ) { Arborist::Event.create(:node_up, parent_node) }

			let( :node ) do
				obj = super()
				obj.handle_event( down_event )
				obj
			end


			it_behaves_like "an unreachable node"


			it "remains `quieted` even if updated with an error" do
				expect {
					node.update( {error: "Internal error"}, 'webservice' )
				}.to_not change { node.status }.from( 'quieted' )
			end


			it "transitions to `unknown` if its reasons for being quieted are cleared" do
				up_event = Arborist::Event.create( :node_up, parent_node )

				expect {
					node.handle_event( up_event )
				}.to change { node.status }.from( 'quieted' ).to( 'unknown' )
			end


			it "transitions to `disabled` if it's acknowledged" do
				expect {
					node.acknowledge( message: 'Turning this off for now.', sender: 'ged' )
				}.to change { node.status }.from( 'quieted' ).to( 'disabled' )
			end

		end


		describe "in `quieted` status because one of its dependencies is down" do

			let( :down_event ) { Arborist::Event.create(:node_down, sibling_node) }
			let( :up_event ) { Arborist::Event.create(:node_up, sibling_node) }

			let( :node ) do
				obj = super()
				obj.depends_on( 'sibling' )
				obj.handle_event( down_event )
				obj
			end


			it_behaves_like "an unreachable node"


			it "transitions to `unknown` if its reasons for being quieted are cleared" do
				expect {
					node.handle_event( up_event )
				}.to change { node.status }.from( 'quieted' ).to( 'unknown' )
			end


			it "transitions to `disabled` if it's acknowledged" do
				expect {
					node.acknowledge( message: 'Turning this off for now.', sender: 'ged' )
				}.to change { node.status }.from( 'quieted' ).to( 'disabled' )
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
				parent = parent_node
				parent <<
					concrete_class.new('child1') { parent 'the_identifier' } <<
					concrete_class.new('child2') { parent 'the_identifier' } <<
					concrete_class.new('child3') { parent 'the_identifier' }

				expect( parent_node.map(&:identifier) ).to eq([ 'child1', 'child2', 'child3' ])
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
				old_node.status_last_changed = Time.now - 800
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
				expect( node.status_last_changed ).to eq( old_node.status_last_changed )
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
					:dependencies, :status_last_changed
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
				expect( result[:status_last_changed] ).to eq( node.status_last_changed.iso8601 )
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
				node.acknowledge(
					message: 'We know about the fire. It rages on.',
					sender: '1986 Labyrinth David Bowie'
				)
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
			events = node.acknowledge(
				message: "I have a poisonous friend. She's living in the house.",
				sender: 'Seabound'
			)

			expect( events.size ).to eq( 1 )

			expect( events.first ).to be_a( Arborist::Event::NodeAcked )
			expect( events.first.payload ).to include( ack: a_hash_including(sender: 'Seabound') )
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

		it "can be matched with multiple statuses" do
			expect( node ).to match_criteria( status: ['up','warn'] )
			expect( node ).to_not match_criteria( status: 'down' )
			expect( node ).to match_criteria( status: 'up' )
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
				acknowledge( message: "Imma gonna f up yo' sash", sender: "GOD" )
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


	describe "reparenting" do

		before( :each ) do
			@old_parent = concrete_class.new( 'router1' ) do
				description "The first router"
			end
			@new_parent = concrete_class.new( 'router2' ) do
				description "The second router"
			end
			@node = concrete_class.new( 'foo' ) do
				parent 'router1'
				description "The prototypical node"
			end

			@old_parent.add_child( @node )
		end

		let( :node ) { @node }
		let( :old_parent ) { @old_parent }
		let( :new_parent ) { @new_parent }


		it "moves itself to the new node and removes itself from its old parent" do
			expect( old_parent.children ).to include( node.identifier )
			expect( new_parent.children ).to_not include( node.identifier )

			node.reparent( old_parent, new_parent )

			expect( old_parent.children ).to_not include( node.identifier )
			expect( new_parent.children ).to include( node.identifier )
		end


		it "sets its state to unknown if it was down prior to the move" do
			node.update( error: 'Rock and Roll McDonalds' )

			node.reparent( old_parent, new_parent )

			expect( node ).to be_unknown
		end


		it "sets its state to unknown if it was quieted by its parent prior to the move" do
			node.quieted_reasons[ :primary ] = "Timex takes a licking and... well, broke, it looks like."
			node.status = 'quieted'

			node.reparent( old_parent, new_parent )

			expect( node ).to be_unknown
		end


		it "keeps its quieted state if it was quieted by secondary dependency prior to the move" do
			node.quieted_reasons[ :primary ] = "Timex takes a licking and... well, broke, it looks like."
			node.quieted_reasons[ :secondary ] = "Western Union:  The fastest way to send money"
			node.status = 'quieted'

			node.reparent( old_parent, new_parent )

			expect( node ).to be_quieted
		end


		it "keeps its disabled state" do
			node.acknowledge( message: 'Moving the machine', sender: 'Me' )
			expect( node ).to be_disabled

			node.reparent( old_parent, new_parent )

			expect( node ).to be_disabled
		end


		it "keeps its acked state" do
			node.update( {error: 'Batman whooped my ass.'}, 'gotham' )
			node.acknowledge( message: 'Moving the machine', sender: 'Me' )
			expect( node ).to be_acked

			node.reparent( old_parent, new_parent )

			expect( node ).to be_acked
		end

	end

end

