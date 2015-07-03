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
    	every 20.seconds
    	match type: 'host'
    	exclude tag: :laptop
    	use :address
    	exec 'fping'
    end

    Arborist::Monitor 'transient host pings' do
    	every 5.minutes
    	match type: 'host', tag: 'laptop'
        use :address
    	exec 'fping'
    end

Each monitor is given a human-readable description for use in user interfaces, and one or more attributes that describe which nodes should be monitored, how they should be monitored, and how often the monitor should be run.

### Monitor Attributes

#### every( seconds )

Declare the interval between runs of the monitor. The monitor will be skewed by a small amount from this value (unless you specify `splay 0`) to prevent many monitors from starting up simultaneously.

#### splay( seconds )

Manually set the amount of splay (random offset from the interval) the monitor should use. It defaults to `Math.logn( interval )`.

#### exec( command )
#### exec {|node_attributes| ... }
#### exec( command ) {|node_attributes| ... }

Specify what should be run to do the actual monitoring. The first form simply `spawn`s the specified command with its STDIN set to a filehandle that is opened to the node attributes of the nodes to be monitored.

The format of the serialized nodes is one node per line, and each line looks like this:

    «identifier» «attribute1»=«attribute1 value» «attribute2»=«attribute2 value»

Each line should use shell-escaping semantics, so that if an attribute value contains whitespace, it should be quoted, control characters need to be escaped, etc.

For example, the ping checker might receive input like:

    duir address=192.168.16.3
    sidonie address="192.168.16.3"
    yevaud address="192.168.16.10"

The monitor must write results for any of the listed identifiers that require update in the same format to its STDOUT. For the ping check above, the results might look like:

    duir rtt=20ms
    sidonie rtt=103ms
    yevaud rtt= error=Host\ unreachable.

Unlisted attributes are unchanged.  A listed attribute with an empty value is explicitly cleared. An identifier that isn't listed in the results means no update is necessary for that node.

The second form can be used to implement a monitor in Ruby; the block is called with the Hash of node data, keyed by identifier, and it must return a Hash of updates keyed by identifier.

The third form is a combination of the first and second forms: it invokes the block with the node data as in the second form, and then when the block `yield`s, it `spawns` the `command` with its STDIN set to the STDOUT of the block. When the `yield` returns, the STDIN of the block is set to the STDOUT of the spawned program. This is generally intended to provide a custom serialization/deserialization wrapper for external commands. The block can also `yield` additional arguments to the command, which are appended to its `ARGV` before it's `spawn`ed.


#### use( *properties )

Specify the list of properties to provide to the monitor for each node. If this is unspecified, the input to the monitor will be just the list of identifiers.


