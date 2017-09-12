Irken
=======

Irken is an attempt to build a small, functional, IRC client in Tcl/Tk.  It
aims to honor as much of IRC as possible while still remaining small enough to
understand by tinkerers.

In order to keep Irken small, the main file is arbitrarily capped to 1000
lines of non-blank, non-comment code.

Features
--------

- supports multiple IRC servers
- adjustable three-pane interface
- highlights mentions of your nick
- clickable hyperlinks
- topic editing
- event hooks for easy customization
- nick tab completion
- command history
- color and formatting

![Screenshot](https://raw.githubusercontent.com/dlowe-net/irken/master/irken.png)

Running
-------

These instructions are for Linux.  Windows support is unlikely.

1. Install `tcl`, `tcl-tls`, and `bwidget` - you need at least version 8.6 of TCL.
2. SVG rendering for icons currently depends on Imagemagick, which for some bizarre
reason requires the Q16 "extra" codec for SVG to work.  Running `apt search
'libmagickcore q16 extra'` should find the correct package to install on
debian-based distributions.
3. Copy or symlink any desired plugins into into `~/.config/irken/`  You may
   have to make the directory.
4. Run `irken.tcl`. By default, it will create a configuration file that
   connects you to freenode.net and joins the #tcl channel.

Configuration
-------------

On startup, if no configuration files are found, a file will be created at
`~/.config/irken/irken.tcl` with a server entry.  Any files ending with
`.tcl` will in the configuration directory will be executed in alphabetical
order.  Since configuration is done with normal Tcl files, theoretically any
customization can be achieved.

Servers are configured with this command:

    server <server ID> <options>

The server ID must not contain spaces.  The options are these:

* `-host` (required) server hostname
* `-nick` (required) nick for connecting to server
* `-port` (optional) server port for connection.  Defaults to 6667 if -secure is
  False, or 6697 if secure is True.
* `-pass` (optional) password for server connection
* `-secure` (optional) use an encrypted connection if True
* `-autoconnect` (optional) connect to server on startup if True
* `-autojoin` (optional) a list of channels to join.  specified like `{"#one" "#two"}`

You may also wish to try some custom fonts, which you can do like this:

    font configure Irken.Fixed -family "Cousine" -size "10"

Built-in commands
-----------------

* `/CLOSE [<channel>]` - remove the channel from the UI, leaving it if necessary
* `/EVAL <command>` - evaluate a TCL command, and display the result
* `/JOIN <channel>` - join a channel on the current server
* `/ME <action>` - send an action to the channel/person
* `/MSG <nick> <message>` - opens a channel and sends a private message to another person.
* `/PART [<channel>]` - leave a channel on the current server
* `/QUERY <nick>` - open a channel to privately message another person
* `/RELOAD` - reload the whole app.  Used mostly for development.
* `/SERVER <server id>` - connect to a server.  The server must already be configured.
* `/<anything else>` - sends the string verbatim to the server.

Keyboard commands
-----------------

* `Control-PageUp` / `Control-PageDown` - navigates to prev/next channel
* `PageUp` / `PageDown` - pages up and down on the current window
* `Up arrow` / `Down arrow` - on command line, goes into the past or future in the command history
* `Tab` - on command line, completes nick at the cursor.  Press tab again for
next match.
* `Return` - on topic line, sets the topic to whatever is in the text box
* `Return` - on command line, either does the command or sends a message to the
  current channel.
* `Control-space` - navigate to the next channel where there are unread messages.

Plugins
-------

Plugins are implemented as Tcl files which are loaded on startup.  Typically, a
plugin will install hooks to add commands or respond to messages.  Hooks are
defined with the following command:

    hook <trigger> <handle> <priority> <parameter list> <code>

When a hook's trigger occurs, each hook is called in order of priority.  The
hook's handle should be unique, and is used so that the hook may be redefined.

In Irken, triggers are of the form `handleMESSAGE`, `ctcpMESSAGE`, or
`cmdCOMMAND`.  The priority of the normal irken handling of a hook is 50.
These hooks should always execute, since much of the UI depends on them.  The
priority of normal irken message display is set to 75, so that plugins may
block or change messages before they are displayed.

`handleMESSAGE` hooks are passed a serverid and message, where message is a
dict containing the fields:

- `src`: the source of the message
- `user`: username of the source
- `host`: hostname of the source
- `cmd`: command of the message
- `args`: a list of the arguments for the command
- `trailing`: IRC has a special argument that comes after a colon (`:`).  This
  argument is stored here, but is also duplicated as the last argument in args.
- `line`: the raw line from the server

`cmdCOMMAND` hooks are passed a serverid and the string following the command.

A hook may return in one of three ways:

- `return -code continue <list>` - continues processing to the next hook, but
  the parameter list will be set to the return value.
- `return -code break` - stops hook processing.
- normal return - continues processing to the next hook, ignoring the return
  value.

Some useful hooks:

- `handle001` - used for when the user is logged into the server and ready
- `handlePRIVMSG` - used for when a message is received on a channel or privately

Make sure to look at the included plugins for inspiration!

Planned
-------

- remove channel button
- proper MODE message handling
- CAP awareness
- Netsplit detection
