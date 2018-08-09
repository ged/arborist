# To-Do

## Third Release (0.3)

### Command line

* Add a 'lint' check, to provide warnings for common misconfigurations
  * Host nodes without any addresses attached

### Setup/Installation

* Add a CLI for generating a basic setup and then adding nodes/monitors/observers to it.

### Manager

* Potential federation / referral for sibling managers
* Add optional authentication support (ZAUTH)


### Nodes

* Allow 'address' host DSL to accept multiple addresses in one call
* Allow disabling an ACKed node (kschies)


### Observers

 * Action dependencies -- as an example, if an action sends an email, don't trigger if the email service is offline. Potential action "chains", ie: If the email service is down, use a separate out-of-band action that sends SMS.

 * Flapping state detection



### Monitors

* Add a one-shot runner command for development of monitors. Loads and runs a monitor one time, maybe with some output describing how often it'd run, what its skew is, etc. [will@laika]

* Add some default monitor types and utilities
  - ftp
  - imap
  - pop
  - smtp

