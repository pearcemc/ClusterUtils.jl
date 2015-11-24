
module ClusterUtils

export lookup, filterpaths, dictify, save, load
export @timeit
export describepids, localpids
export getrepresentation, display
export Doable, sow, reap, reaprefs
export collectmsgs, collectmsgsatpid, collectmsgsatmaster, swapmsgs

# FINDING, STORING, LOADING DATA

function lookup(modname::Module, srchterm::Regex)
    vars = names(modname, true)
    indx = map((n)->ismatch(srchterm, string(n)), vars);
    vars[indx]
end

function filterpaths(dir, srch)
    srchr = Regex(srch)
    absdir = abspath(dir)
    fpths = readdir(absdir)
    matches = filter((name)->ismatch(srchr,name), fpths)
    map((nm)->absdir*"/"*nm, matches)
end

function dictify(syms::Symbol...; mod=Main)
    Dict([s => eval(mod, s) for s in syms])
end

function save(fp::AbstractString, A::Any)
    f = open(fp, "w+")
    serialize(f, A)
    close(f)
end

function save(fp::AbstractString, syms::Symbol...)
    D = dictify(syms...)
    save(fp, D)
end

function load(fp)
    f = open(fp, "r")
    O = deserialize(f)
    close(f)
    O
end

# PERFMORMANCE TESTING

macro timeit(reps, expr)
   quote
       mean([@elapsed $expr for i in 1:$reps])
   end
end


# DESCRIBING NETWORK TOPOLOGY

@doc """
Make a function that filters out strings matching the hostname of process 1.\n
""" ->
function makefiltermaster()
    master_node = strip(remotecall_fetch(readall, 1, `hostname`), '\n')
    function filtermaster(x)
        x != master_node
    end
    filtermaster
end


function describepids(pids; filterfn=(x)->true)

    # facts about the machines the processes run on
    machines = [strip(remotecall_fetch(readall, w, `hostname`), '\n') for w in pids]
    machine_names = sort!(collect(Set(machines)))
    machine_names = filter(filterfn, machine_names)
    num_machines = length(machine_names)

    # nominate a representative process for each machine, and define who it represents
    representative = zeros(Int64, num_machines)
    constituency = Dict()
    for (i,name) in enumerate(machine_names)
        constituency[i] = Int64[]
        for (j,machine) in enumerate(machines)
            if name==machine
                push!(constituency[i], pids[j])
                representative[i] = pids[j]
            end
        end
    end

    # assemble the groups of processes keyed by their representatives
    topo = Dict{Int64, Array{Int64, 1}}()
    for (i,p) in enumerate(representative)
        topo[minimum(constituency[i])] = constituency[i]
    end

    topo
end

@doc """
Return information about the resources (pids) available to us grouped by the machine they are running on.\n
keyword argument: remote=0 (default) specifies remote machines; remote=1 the local machine; remote=2 all machines.\n 
length(topo) gives the number of unique nodes.\n
keys(topo) gives the id of a single process on each compute node.\n
values(topo) gives the ids of all processes running on each compute node.
""" ->
function describepids(; remote=0)
    pids = procs()
    if remote==0
        filterfn = makefiltermaster()
    elseif remote==1
        filtertrue = makefiltermaster()
        filterfn = (x)->!filtertrue(x)
    elseif remote==2
        filterfn=(x)->true
    end
    describepids(pids; filterfn=filterfn)
end

function localpids()
    topo = describepids(remote=1)
    topo[collect(keys(topo))[1]]
end

# CHUNKING OF ARRAYS

function evenchunks(dims::Tuple{Int, Int}; axis=1, remote=0)

    remtop = describepids(remote=remote)
    ncomps = length(keys(remtop))

    chunksz = round(Int, dims[axis] / ncomps)
    chunkst = []
    chunknd = []
    for i in 0:(ncomps-1)
        st = 1 + i*chunksz
        nd = (i+1)*chunksz
        push!(chunkst, st)
        push!(chunknd, nd)
    end

    chunkdc = Dict()
    for (i,k) in enumerate(keys(remtop))
        for p in remtop[k]
            chunkdc[p] = (chunkst[i], chunknd[i])
        end
    end

    chunkdc
end

# REPRESENTATION OF SHARED ARRAYS THAT WORKS FOR SAs ON REMOTE HOSTS

function getrepresentation(S)
    buf = IOBuffer()
    td = TextDisplay(buf)
    Base.Multimedia.display(td, S)
    str = takebuf_string(buf)
    return str
end

function Base.display(S::SharedArray)
    validpid = minimum(S.pids)
    repr = @fetchfrom validpid getrepresentation(S)
    print_with_color(:bold, repr)
end



# FOR BROADCASTING VARIABLES

function sow(p::Int64, nm::Symbol, val; mod=Main)
    remotecall(Main.eval, p, mod, Expr(:(=), nm, val))
end

function sow(pids::Array{Int64, 1}, name::Symbol, value; mod=Main)
    refs = Array{RemoteRef, 1}([])
    @sync for p in pids
        @async push!(refs, sow(p, name, value; mod=mod))
    end
    refs
end

function sow(name::Symbol, value; mod=Main)
    pids = workers()
    sow(pids, name, value; mod=mod)
end

# HARVESTING VALUES OR REFERENCES FROM REMOTES

Doable = Union{Symbol, Expr}

function reap(pids::Array{Int64, 1}, doable::Doable; callstyle=remotecall_fetch, returntype=Any)
    results = Dict{Int64, returntype}()
    @sync for k in pids
        @async results[k] = callstyle(Main.eval, k, doable)
    end
    results
end

function reap(doable::Doable; callstyle=remotecall_fetch, returntype=Any)
    pids = workers()
    reap(pids, doable; callstyle=callstyle, returntype=returntype) 
end

function reap(pid::Int64, doable::Doable; callstyle=remotecall_fetch, returntype=Any)
    pids = [pid];
    reap(pids, doable; callstyle=callstyle, returntype=returntype) 
end

function reaprefs(pids, doable::Doable; returntype=Any)
    reap(pids, doable; callstyle=remotecall, returntype=returntype) 
end

#MESSAGING DICTIONARY SYNCHRONISATION

function collectmsgs(msgname::Symbol)
    @sync for j in Main.eval( :(keys($(msgname))) )
        @async begin
        val = remotecall_fetch(Main.eval, j, Expr(:call, :getindex, msgname, j))
        Main.eval(Expr(:call, :setindex!, msgname, val, j)) 
        end
    end 
end

function collectmsgs(msgname::Symbol, msglocal::Dict)
    @sync for j in keys(msglocal)
        @async begin
        msglocal[j] = remotecall_fetch(Main.eval, j, Expr(:call, :getindex, msgname, j))
        end
    end 
    msglocal
end

function collectmsgs(msgname::Symbol, pids::Array{Int64, 1})
    msglocal = Dict{Int64, Any}()
    @sync for j in pids
        @async begin
        msglocal[j] = remotecall_fetch(Main.eval, j, Expr(:call, :getindex, msgname, j))
        end
    end 
    msglocal
end

function swapmsgs(pids::Array{Int64,1}, msgname::Symbol)
    @sync for pid in pids
         @async remotecall_wait(collectmsgs, pid, msgname)
    end   
end

function swapmsgs(msgname::Symbol)
    pids = workers()
    swapmsgs(pids, msgname) 
end

end
