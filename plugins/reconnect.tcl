### reconnect Irken Plugin - copy to ~/.config/irken/ to use.
#
# Description:
#
#   Automatically reconnects a server that has been disconnected, using
# limited exponential falloff plus jitter on failure.
#

namespace eval reconnect {
    namespace import ::irken::*
    variable failures {}

    hook connected reconnect 50 {serverid} {
        variable failures
        dict unset failures $serverid
    }
    
    hook disconnection reconnect 50 {serverid} {
        variable failures

        set fails [lindex [dict incr failures $serverid] 1]
        set capped [expr {min(10, $fails)}]
        set wait [expr {int(100 * (pow(2.0, $capped) + rand()))}]
        irken::addchantext $serverid [format "Reconnecting in %.2f seconds (attempt %d)..." [expr {$wait / 1000.0}] $fails] -tags system
        after $wait [list ::irken::connect $serverid]
    }
}
