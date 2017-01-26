
# ClusterUtils.jl

Message passing, control and display utilities for distributed and parallel computing. The primary use case is convenience in:

 - assigning variables on remote processes.
 - computing on remote variables many times.
 - retrieving some facts about variables on remote processes.

If you were hoping for parallel behaviour that looks something like:

```julia

reap(2, :(x = myid()))
#Dict{Int64,Any} with 1 entry:
#  2 => 2

reap(2, :(sqrt(x)))
#Dict{Int64,Any} with 1 entry:
#  2 => 1.41421

sow(2, :y, myid())
#Future(2,1,16,Nullable{Any}())

reap(2, :y)
#Dict{Int64,Any} with 1 entry:
#  2 => 1
```

Then this package may be of interest.

## Compatibility

Current version of this repository requires Julia 0.5.

## Map and reduce type operations.

Traditional map-reduce can be effected by use of `reap`.

Suppose we want to add together 3 vectors of 5 squared uniform random variables:

```julia
using ClusterUtils

pids = [2,3,4]
reduce(+, values(reap(pids, :(rand(5).^2)))) 
#5-element Array{Float64,1}:
# 1.61008 
# 2.43127 
# 2.10954 
# 0.696425
# 3.06037 
```

We can map the results of an evaluation to a symbol on remote processes using `sow`. This makes the symbol's value available for future operations.
The default is that the symbol has global scope (keyword arg `mod=Main`). 
We can retrieve the value of a symbol on remote processes using `reap`.

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

sow(4, :specificbob, :(sqrt(myid())); mod=ClusterUtils)
#RemoteRef{Channel{Any}}(4,1,933)

@fetchfrom 4 ClusterUtils.specificbob
#2.0
```

We can also map to slices, keys, etc. like so:

```julia
pids = [2,3,4]
sow(pids, :bar, :(randn(4,4)))

sow(pids, :(bar[1:2,:]), 0)

reap(pids, :bar)[pids[1]]
#4x4 Array{Float64,2}:
#  0.0        0.0      0.0        0.0     
#  0.0        0.0      0.0        0.0     
# -1.15992   -1.45188  0.282003  -0.135126
#  0.652393  -1.14758  0.648452   1.17555 


sow(pids, :somedict, :(Dict(:buzz=>randn(2,2), :badger=>"hello")));
sow(pids, :(somedict[:buzz][:,:]), pi);

reap(pids, :(somedict[:buzz]))[pids[1]]
#2x2 Array{Float64,2}:
# 3.14159  3.14159
# 3.14159  3.14159
```



## Network topology

The next example is of a utility to describe which processes are on which hosts as this is useful for SharedArray creation.
`describepids` returns a dict where the keys are processes on unique hosts, the keyed value represents all processes on that host.
With no arguments only remote processes are described.

```julia
@everywhere using ClusterUtils

topo = describepids() # only procs on remote machines
#Dict{Any,Any} with 2 entries:
#  13 => [2,3,4,5,6,7,8,9,10,11,12,13]
#  25 => [14,15,16,17,18,19,20,21,22,23,24,25]

topo = describepids(remote=1) # only procs on local machine
#Dict{Any,Any} with 1 entry:
#  1 => [1]

topo = describepids(remote=2) # procs on all machines
#Dict{Any,Any} with 3 entries:
#  13 => [2,3,4,5,6,7,8,9,10,11,12,13]
#  25 => [14,15,16,17,18,19,20,21,22,23,24,25]
#  1  => [1]

topo = describepids(procs(); filterfn=(x)->ismatch(r"tesla", x)) # custom filter based on `hostname`
#Dict{Any,Any} with 2 entries:
#  13 => [2,3,4,5,6,7,8,9,10,11,12,13]
#  25 => [14,15,16,17,18,19,20,21,22,23,24,25]
```

## Broadcasting `SharedArray` objects

Using the network topology information we can setup `SharedArray` objects such that memory is shared between processes on the same machines
This is currently not recommended for heavy use (OK to setup at the beggining of an algorithm, but not multiple calls per second).

```julia
topo = describepids();
reps = collect(keys(topo)) #a representative process from each machine
#5-element Array{Int64,1}:
#  86
#  98
#  74
#  62
# 110


# initialise a SharedArray using the same random matrix on each machine:
broadcast_shared(topo, Float32, rand(4,4), :foo); 

sow(reps, :(foo[1,:]), :(map(Float32, pi)))

someworkers = reps+1
#5-element Array{Int64,1}:
#  87
#  99
#  75
#  63
# 111

workerslices = reap(someworkers, :(foo[1:2,:]));

workerslices[someworkers[1]]
#2x4 Array{Float32,2}:
# 3.14159   3.14159   3.14159   3.14159 
# 0.317024  0.381314  0.726252  0.709073
```

## Concatentation with `stitch`

The `stitch` function concatenates objects stored on remotes in the ascending order of their process numbers

```julia
pids
#5-element Array{Int64,1}:
#  86
#  98
#  74
#  62
# 110

sow(pids, :x, :(myid()^2*randn(3)))

stitch(pids, :x)
#15-element Array{Float64,1}:
#   -724.409
#   4207.66 
#   2020.86 
#  -8955.88 
#  -8417.0  
#   5453.98 
#  -3782.38 
#   2769.99 
#   7397.81 
# -12128.3  
#  -2169.37 
#   -772.394
# -10736.4  
#  -8078.21 
# -31016.8 
```

## Message passing (experimental)

Here we use some remote `MessageDict`s to swap messages between different processes.

```julia
@everywhere using ClusterUtils

remotes = workers()

#24-element Array{Int64,1}:
#  2
#  3
#  4
#  [...]

msgmaster = Dict(k=>0 for k in remotes);
sow(remotes, :somemsg, msgmaster );

isdefined(:somemsg)
#false

@fetchfrom remotes[1] somemsg
#ClusterUtils.MessageDict
#Dict{Int64,Any} with 24 entries:
#  2  => 0
#  11 => 0
#  7  => 0
# [...]

[@spawnat k somemsg[k] = 2k for k in remotes];

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

Carrying on from the previous example. Suppose we did not need to `swapmsgs` between workers, but instead only to aggregate the results on a single process.
Here we use a Dict held on process 1 to aggregate work done on remote servers.

```julia
collectmsgs(:somemsg, remotes)
#Dict{Int64,Any} with 24 entries:
#  2  => 4
#  16 => 32
#  11 => 22
# [...]
```

## Storing and recovering data

Two functions `save` and `load` are provided for conveniently storing and recovering data, built on top of `Base.serialize`. First usage is for objects of `Any` type:

```julia
save("temp.jlf", randn(5))

load("temp.jlf")
#5-element Array{Float64,1}:
# -1.41679  
# -1.2292   
#  0.103825 
#  0.0804196
#  1.4737   
```

Second usage takes a list of symbols for variables defined in Main (default kwarg `mod=Main`), turns them into a `Dict` and `save`s that.

```julia
R = [1,2,3];

X = "Fnordic";

save("temp.jlf", :X, :R)

load("temp.jlf")
#Dict{Symbol,Any} with 2 entries:
#  :R => [1,2,3]
#  :X => "Fnordic"
```


## Patch: Displaying SharedArrays

Display of `SharedArray`s is not well behaved when all processes with access to the underlying shared memory are on a remote host.

## Patch: garbage collection error

The module also includes a workaround for issue #14445, which is related to garbage collection interrupts from remotecall operations.
