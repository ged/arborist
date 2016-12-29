# Monitors

Monitors are loaded in a fashion similar to the way nodes describing the network topology are
loaded: you provide a Enumerator that yields Arborist::Monitor objects to the #load_monitors method
of an Arborist::MonitorRunner object. The `Arborist::Monitor.each_in` method, given a path to a directory containing `.rb` files that declare one or more monitors, will return such an Enumerator, but you could also use this to load monitor descriptions from any source you prefer, e.g., LDAP, a RDBMS, etc.


## Declaration DSL

To facilitate describing monitors to run, Arborist::Monitor also provides a DSL-like syntax for constructing them.

For example, this would declare two monitors, one which pings every 'host' node except those tagged as laptops in the network every 20 seconds, and the other which pings 'host' nodes tagged as laptops every 5 minutes.

    # monitors/pings.rb
    require 'arborist/monitor'

    Arborist::Monitor 'ping check' do
        key :pingcheck
        every 20.seconds
        match type: 'host'
        exclude tag: :laptop
        use :address
        exec 'fping'
    end

    Arborist::Monitor 'transient host pings' do
        key :pingcheck
        every 5.minutes
        match type: 'host', tag: 'laptop'
        use :address
        exec 'fping'
    end

Each monitor is given a human-readable description for use in user interfaces, and one or more attributes that describe which nodes should be monitored, how they should be monitored, and how often the monitor should be run.

### Monitor Attributes

#### key

Declare a namespace for the monitor. The error status for a node is keyed by this value, so that monitors with different keys don't clear each other's errors.

This attribute is mandatory.

#### description

Set a human-readable description for the monitor, for use in interfaces or logs.

This attribute is mandatory.

#### every( seconds )

Declare the interval between runs of the monitor. The monitor will be skewed by a small amount from this value (unless you specify `splay 0`) to prevent many monitors from starting up simultaneously.

#### splay( seconds )

Manually set the amount of splay (random offset from the interval) the monitor should use. It defaults to `Math.logn( interval )`.

#### exec( command )
#### exec {|node_attributes| ... }
#### exec( module )

Specify what should be run to do the actual monitoring. The first form simply `spawn`s the specified command with its STDIN opened to a stream of serialized node data.

By default, the format of the serialized nodes is one node per line, and each line looks like this:

    «identifier» «attribute1»=«attribute1 value» «attribute2»=«attribute2 value»

Each line should use shell-escaping semantics, so that if an attribute value contains whitespace, it should be quoted, control characters need to be escaped, etc.

For example, the ping checker might receive input like:

    duir address=192.168.16.3
    sidonie address="192.168.16.3"
    yevaud address="192.168.16.10"

If the command you are running doesn't support this format, you can override this in one of two ways.

If your command expects the node data as command-line arguments, you can provide a custom `exec_arguments` block. It will receive an Array of Arborist::Node objects and it should generate an Array of arguments to append to the command before `spawn`ing it.

    exec_arguments do |nodes|
        # Build an address -> node mapping for pairing the updates back up by address
        @node_map = nodes.each_with_object( {} ) do |node, hash|
            address = node.address
            hash[ address ] = node
        end
        
        @node_map.keys
    end

If your command expects the node data via `STDIN`, but in a different format, you may declare an `exec_input` block. It will be called with the same node array, and additionally an IO open to the STDIN of the running command. This can be combined with the `exec_arguments` block, if you're dealing with something really weird.

    exec_input do |nodes, writer|
        # Build an address -> node mapping for pairing the updates back up by address
        @node_map = nodes.each_with_object( {} ) do |node, hash|
            address = node.address
            hash[ address ] = node
        end
        
        writer.puts( node_map.values )
    end

The monitor must write results for any of the listed identifiers that require update in the same format to its STDOUT. For the ping check above, the results might look like:

    duir rtt=20ms
    sidonie rtt=103ms
    yevaud rtt= error=Host\ unreachable.

If the program writes its output in some other format, you can provide a `handle_results` block. It will be called with the program's `STDOUT` if the block takes one argument, and if it takes an additional argument its `STDERR` as well. It should return a Hash of update Hashes, keyed by the node identifier it should be sent to.

    handle_results do |pid, out, err|
        updates = {}
        
        out.each_line do |line|
            address, status = line.split( /\s+:\s+/, 2 )
            
            # Use the @node_map we created up in the exec_arguments to map the output
            # back into identifiers. Error-checking omitted for brevity.
            identifier = @node_map[ address ].identifier

            # 127.0.0.1 is alive (0.12 ms)
            # 8.8.8.8 is alive (61.6 ms)
            # 192.168.16.16 is unreachable
            if status =~ /is alive \((\d+\.\d+ ms)\)/i
                updates[ identifier ] = { ping: { rtt: Float($1) } }
            else
                updates[ identifier ] = { error: status }
            end
        end

        updates
    end

Unlisted attributes are unchanged.  A listed attribute with an empty value is explicitly cleared. An identifier that isn't listed in the results means no update is necessary for that node.

If you find yourself wanting to repeat one or more of the exec callbacks, you can also wrap them in a module and call `exec_callbacks` with it.

The second and third forms can be used to implement a monitor in Ruby. In the second, the block is called with the Hash of node data, keyed by identifier, and it must return a Hash of updates keyed by identifier. The third form expects any object that responds to `#run`, which will be invoked the same way as the block.


#### use( *properties )

Specify the list of properties to provide to the monitor for each node. If this is unspecified, the input to the monitor will be just the list of identifiers.



    # Does everything in Ruby; gets the Array of Nodes as arguments to the block, expected to
    # return a Hash of updates keyed by node identifier
    exec do |nodes|
        
    end


    # Runs an external
	exec 'fping', '-e', '-t', '150'

