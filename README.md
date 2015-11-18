
# ClusterUtils.jl

Message passing, control and display utilities for distributed and parallel computing.

## Discovering network topology

The next example is of a utility to describe which processes are on which hosts as this is useful for SharedArray creation.
`describepids` returns a dict where the keys are processes on unique hosts, the keyed value represents all processes on that host.
With no arguments only remote processes are described.

```julia
@everywhere using ClusterUtils

describepids()
#Dict{Any,Any} with 2 entries:
#  13 => [2,3,4,5,6,7,8,9,10,11,12,13]
#  25 => [14,15,16,17,18,19,20,21,22,23,24,25]

describepids(remote=1)
#Dict{Any,Any} with 1 entry:
#  1 => [1]

describepids(remote=2)
#Dict{Any,Any} with 3 entries:
#  13 => [2,3,4,5,6,7,8,9,10,11,12,13]
#  25 => [14,15,16,17,18,19,20,21,22,23,24,25]
#  1  => [1]

describepids(procs(); filterfn=(x)->ismatch(r"tesla", x)) #filter based on `hostname`
#Dict{Any,Any} with 2 entries:
#  13 => [2,3,4,5,6,7,8,9,10,11,12,13]
#  25 => [14,15,16,17,18,19,20,21,22,23,24,25]
```
## Displaying SharedArrays

Display of `SharedArray`s is not well behaved when all processes with access to the underlying shared memory are on a remote host.

```julia
julia> using ClusterManagers

julia> remotes = addprocs(SlurmManager(24), nodes=2)
#srun: job 1892137 queued and waiting for resources
#srun: job 1892137 has been allocated resources
#24-element Array{Int64,1}:t of 24
#  2
#  3
#  4
#  5
#  6
# [...]

S = SharedArray(Int, (3,4), init = S -> S[localindexes(S)] = myid(), pids=[2,3,4,5])
#3x4 SharedArray{Int64,2}:
# #undef  #undef  #undef  #undef
# #undef  #undef  #undef  #undef
# #undef  #undef  #undef  #undef

@everywhere using ClusterUtils

T = SharedArray(Int, (3,4), init = S -> S[localindexes(S)] = myid(), pids=[2,3,4,5])
#3x4 SharedArray{Int64,2}:
# 2  3  4  5
# 2  3  4  5
# 2  3  4  5
```

## Sending variables to remotes

We can bind something to a symbol on remote processes using `sow` default symbol has global scope (keyword arg `mod=Main`). 
We can retrieve the thing bound to a symbol on remote processes using `reap`.

```julia
sow(3, :bob, pi^2)
#RemoteRef{Channel{Any}}(3,1,877)

@fetchfrom 3 bob
#9.869604401089358

sow([2,3,4], :morebob, :(100 + myid()))
#3-element Array{Any,1}:
# RemoteRef{Channel{Any}}(2,1,879)
# RemoteRef{Channel{Any}}(3,1,880)
# RemoteRef{Channel{Any}}(4,1,881)

reap([2,3,4], :morebob)
#Dict{Any,Any} with 3 entries:
#  4 => 104
#  2 => 102
#  3 => 103

sow(:yabob, :(1000 - myid()))
#24-element Array{Any,1}:
# RemoteRef{Channel{Any}}(2,1,885) 
# RemoteRef{Channel{Any}}(3,1,886) 
# RemoteRef{Channel{Any}}(4,1,887) 
# [...]

reap(:yabob)
#Dict{Any,Any} with 24 entries:
#  2  => 998
#  16 => 984
#  11 => 989
# [...]

sow(4, :specificbob, :(sqrt(myid())); mod=ClusterUtils)
#RemoteRef{Channel{Any}}(4,1,933)

@fetchfrom 4 ClusterUtils.specificbob
#2.0

```

## Message passing

Here we use some remote `MessageDict`s to swap messages between different processes.

```julia
@everywhere using ClusterUtils

remotes = workers()
#24-element Array{Int64,1}:
#  2
#  3
#  4
#  [...]

sow(remotes, :somemsg, MessageDict() );

isdefined(:somemsg)
#false

@fetchfrom remotes[1] somemsg
#ClusterUtils.MessageDict
#Dict{Int64,Any} with 24 entries:
#  2  => 0
#  11 => 0
#  7  => 0
# [...]

[@spawnat k somemsg.msgs[k] = 2k for k in remotes];

@fetchfrom remotes[1] somemsg
#ClusterUtils.MessageDict
#Dict{Int64,Any} with 24 entries:
#  2  => 4
#  11 => 0
#  7  => 0
#  [...]

swapmsgs(remotes, :somemsg)

@fetchfrom remotes[1] somemsg
#ClusterUtils.MessageDict
#Dict{Int64,Any} with 24 entries:
#  2  => 4
#  11 => 22
#  7  => 14
#  [...]

ClusterUtils.@timeit 100 swapmsgs( workers(), :somemsg )
#0.016565912109999994
```

Here we use a MessageDict held on process 1 to aggregate work done on remote servers.

```julia
@everywhere using ClusterUtils

remotes = workers()
#24-element Array{Int64,1}:
#  2
#  3
#  4
#  [...]

msgmaster = MessageDict(remotes, randn(3))
#ClusterUtils.MessageDict
#Dict{Int64,Any} with 24 entries:
#  2  => [0.0,0.0,0.0]
#  16 => [0.0,0.0,0.0]
#  11 => [0.0,0.0,0.0]
#  [...]

msgnameonremotes = :msgremote
#:msgremote

sow(msgnameonremotes, msgmaster);

[@spawnat k msgremote[k] = randn(3) for k in remotes];

remotecall_fetch(eval, remotes[1], msgnameonremotes)
#ClusterUtils.MessageDict
#Dict{Int64,Any} with 24 entries:
#  2  => [2.515734256502936,1.521004010709128,-0.2635622270511424]
#  11 => [0.0,0.0,0.0]
#  7  => [0.0,0.0,0.0]
#  [...]

collectmsgsatmaster(msgnameonremotes, msgmaster)
#ClusterUtils.MessageDict
#Dict{Int64,Any} with 24 entries:
#  2  => [2.515734256502936,1.521004010709128,-0.2635622270511424]
#  16 => [0.7882547595085879,-0.2596569269024375,0.22735615312570082]
#  11 => [-0.9067633589631379,-0.5787807122606919,0.7902320035717597]
#  [...]
```



