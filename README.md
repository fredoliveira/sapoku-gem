# Intro to the SAPOKU gem

The Sapoku gem manages the creation of LXC-based containers on the SmartcloudPT platform. These containers, called `Tadpoles` and exposed through the `Tadpole` class represent chunks of a given operating system. They provide filesystem separation, as well as CPU and memory containment. 

## Bootstrapping a new Tadpole

* `require 'sapoku'`
* `t = Tadpole.new(appname)`
* `t.save`
* `t.bootstrap`