# To-Do

## First Release (0.1)

* README, Tutorial, Setup docs

* Performance/profiling examination


### Observers

* Add `exclude` to observers DSL
  * modify tree api to accept negative criteria to subscribe
	* pass to manager's create_subscription()
	* alter subscription to no-op if event matches negative stuff


### Monitor

* Add some default monitor types and utilities
  - ftp
  - imap
  - pop
  - smtp

* Write a gem for `fping` monitor 

* Redo the select loop of the UDP socket monitor to wait for them in parallel instead of in series.


## Second Release (0.2)

### Setup/Installation

* Add a CLI for generating a basic setup and then adding nodes/monitors/observers to it.
* Potential federation / referral for sibling managers

### Nodes

* Ask a node (via tree-api or otherwise) what nodes it affects (immediate children, secondary dependents)

### Observers

 * Action dependencies -- as an example, if an action sends an email,
   don't trigger if the email service is offline.  Potential action
   "chains", ie:  If the email service is down, use a separate
   out-of-band action that sends SMS.
