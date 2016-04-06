# To-Do

## First Release (0.1)

* README, Tutorial, Setup docs


### Manager

* Include 'quieted' in the list of states that are not reachable
  via normal node iteration

* Only restore timestamps from serialized node dependencies, not the deps themselves.

* Broadcast system events:
    - `sys.node.added`
    - `sys.node.removed`
    - `sys.startup`
    - `sys.shutdown`


(Hook state machine to generate events for state changes)
Already done
    - `node.up`
    - `node.down`
    - `node.disabled`
    - `node.quieted`
    - `node.acked`
    - `node.delta`
    - `node.updated`
    - `sys.reloaded`


### Observers

* Re-subscribe on `sys.startup`, `sys.reloaded`, `sys.node.added`


### Nodes

* Allow expressing arbitrary, secondary dependencies between nodes (FTP under host X can't operate if LDAP under host N is down, etc)

* Allow a service node to not inherit all of its host's addresses (i.e., be bound to one address only or whatever)


## Second Release (0.2)

### Setup/Installation

* Add a CLI for generating a basic setup and then adding nodes/monitors/observers to it.
* Potential federation / referral for sibling managers

### Nodes

* Ask a node (via tree-api or otherwise) what nodes it affects (immediate children, secondary dependents)
