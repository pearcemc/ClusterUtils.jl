
module ClusterUtils

export lookup, filterpaths, dictify, save, load
export describepids, localpids, invtopology, chunkit
export Doable, sow, reap, reaprefs
export @reap, @sow
export getrepresentation, display, broadcast_shared

#export collectmsgs, collectmsgsatpid, collectmsgsatmaster, swapmsgs
#export stitch

include("topology.jl") #finding, decribing and setting vars on other pids
include("reap.jl") #main message passing utilities
include("utils.jl") #misc utilities
include("experimental.jl") #other styles of message passing, not tested as much
include("patches.jl") #patches for issues to do with HPC

end  #module ClusterUtils

