## v0.3.0 [2018-08-29] Michael Granger <ged@FaerieMUD.org>

Enhancements:

- Add a `run_once` command for testing monitors
- Acking an already acked node transitions the node to disabled.
- Add raw formatting for YAML and JSON to the tree command.
- Optionally continue attempting to ack/clear nodes if some are
  invalid.
- Expose socket batch size to configurability.

Fixes:

- Use the proper exception when raising errors from the client,
  instead of RuntimeError.



## v0.2.0 [2018-08-08] Michael Granger <ged@FaerieMUD.org>

Breaking:

- Collapse startup event into the heartbeat event
- Rename some actions in the Tree API for clarity
  * Rename `list` to `fetch`
  * Rename `fetch` to `search`
- Don't let #add_node automatically replace nodes with the same
  identifier, instead leaving the remove step to the caller.

Enhancements:

- Add acknowledgement changes to delta events.
- Add batching to the socket monitor
- Add a --path argument to the 'tree' command, that displays parents
  to the root when specified.
- Add a DSL method for returning a Client singleton.
- Provide a way to disable colors for misbehaving terms.
- Allow ack/unack on the root node to quiet and re-enable the tree.
- Retain the previous time a node's status changed, for easy time
  deltas between state transitions.
- Add the node type as additional metadata to node events.
- Add node parent to the default node event class, stick to symbols
  for hash keys.
- Allow "OR-ing" of statuses/identifiers/types when matching.
- Make the default node search return all nodes
  All nodes in the tree are returned by default now. You can omit
  unreachable nodes with the `exclude_down` option/method.
- Add a warning state to nodes
- Add an optional 'hostname' label to the host node DSL.
  This is a convenience matcher for selecting by host, since
  identifiers are designed to be opaque, and description fields are
  more human readable.
- Add a configurable default splay for all instantiated Monitors.
- Allow separate monitors to run in parallel.
- Make ack friendlier for batch updates, prompt for missing values.
- Add a 'summary' command, for quick display of existing problems.
- Use the uid instead of gecos for default ack sender.
- Add a "reset" command to the client.
- Add wildcard matching to node events.
- Add introspection on secondary dependencies to the Tree API
- Add an `ack` command
- Convert to CZTop for ZeroMQ
- Add a block to Node.parent_type to allow for more-expressive
  declarations
- Normalize and emit better error messages from client commands.

Bugfixes:

- Fix behavior for child nodes whose parent transitions from 'down' to
  'warn'.
- Don't make loading config conditional, so loading config path from
  ENV works as intended.
- Propagate ack and unack events to parent nodes.
- Keep the observer daemon running if observer action blocks raise
  exceptions.
- Throw a client error if attempting to graft over a pre-existing node.
- Re-arrange constants to avoid Ruby 2.4 refinement warnings. Lower
  debug output when loading nodes.
- Fix the signature of Arborist::Client#fetch
  It was defaulting trailing-hash arguments to options, which made the
  typical case of fetching with only criteria awkward. This makes the
  atypical case (fetching with options but empty criteria) the awkward
  case instead.


# v0.1.0 [2017-01-01] Michael Granger <ged@FaerieMUD.org>

Initial release.

