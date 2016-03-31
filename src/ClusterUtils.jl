
module ClusterUtils

export lookup, filterpaths, dictify, save, load
export @timeit
export describepids, localpids, invtopology
export chunkit
export getrepresentation, display, broadcast_shared
export Doable, sow, reap, reaprefs
export collectmsgs, collectmsgsatpid, collectmsgsatmaster, swapmsgs
export stitch

import Base.del_client
export Base.del_client 

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


# DESCRIBING NETWORK TOPOLOGY

@doc """
Make a function that filters out strings matching the hostname of process 1.\n
""" ->
function makefiltermaster()
    #master_node = strip(remotecall_fetch(readall, 1, `hostname`), '\n')
    master_node = strip(reap(1, :(gethostname()))[1], '\n')
    function filtermaster(x)
        x != master_node
    end
    filtermaster
end


function describepids(pids; filterfn=(x)->true)

    # facts about the machines the processes run on
    #machines = [strip(remotecall_fetch(readall, w, `hostname`), '\n') for w in pids] #doesn't work on 0.4
    machines = map(p->strip(reap(p, :(gethostname()))[p], '\n'), pids)
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
        c = sort(constituency[i])
        topo[c[1]] = c
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

@doc """
For splitting work evenly across computers.
""" ->
function preferredorder(topology)
    arrtop = reduce(hcat, values(topology))
    arrrow = [arrtop[i,:]' for i in 1:size(arrtop)[1]]
    vec(reduce(vcat, arrrow))
end

function invtopology(topology)
    myrep = Dict()
    for rep in keys(topology)
        for pid in topology[rep]
            myrep[pid] = rep
        end
    end
    return myrep
end

# CHUNKING OF ARRAYS

function chunkit(axlen::Int, ncomps::Int)
    
    chunksz = map(Int64, zeros(ncomps))

    for i in 1:axlen
        chunksz[i%ncomps + 1] += 1
    end

    chunknd = cumsum(chunksz)
    chunkst = vcat(0, chunknd[1:end-1]) + 1

    [chunkst[i]:chunknd[i] for i in 1:ncomps]
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


function broadcast_shared(topo, elty_, value, symb)

    # CONFIG INFO
    reps_ = collect(keys(topo))

    # SHAPE
    T,V = size(value)
 
    # CREATE ON A SINGLE PROCESS ON EACH NODE
    remote_refs = sow(reps, symb, :( copy!(SharedArray($elty_, ($T, $V), pids=[$topo[myid()]]), $value) ));

    # MAKE ARRAY ACCESSIBLE ON ALL OTHER PROCS ON NODE
    @sync for r in reps_
        @async begin
        sow(topo[r], symb, :(fetch($remote_refs[$r])));
        end
    end
end


#workarounds for #14445

function del_client(pg, id, client)
# As a workaround to issue https://github.com/JuliaLang/julia/issues/14445
# the dict/set updates are executed asynchronously so that they do
# not occur in the midst of a gc. The `@async` prefix must be removed once
# 14445 is fixed.
    @async begin
        rv = get(pg.refs, id, false)
        if rv != false
            delete!(rv.clientset, client)
            if isempty(rv.clientset)
                delete!(pg.refs, id)
                #print("$(myid()) collected $id\n")
            end
        end
    end
    nothing
end


# FOR BROADCASTING VARIABLES

Doable = Union{Symbol, Expr}

function yieldfirst(todo::Doable) #required while bug 14445 still around
    return :(yield(); $todo)
end

function sow(pid::Int64, name::Doable, value; mod=Main, callstyle=remotecall_wait)
    todo = Expr(:(=), name, value) 
    callstyle(Main.eval, pid, mod, yieldfirst(todo))
end

function sow(pids::Array{Int64, 1}, name::Doable, value; mod=Main, callstyle=remotecall_wait)
    refs = Dict{Int64, RemoteRef}()
    @sync for p in pids
        @async refs[p] = sow(p, name, value; mod=mod, callstyle=callstyle)
    end
    refs
end

function sow(name::Doable, value; mod=Main, callstyle=remotecall_wait)
    pids = workers()
    sow(pids, name, value; mod=mod, callstyle=callstyle)
end

# HARVESTING VALUES OR REFERENCES FROM REMOTES

function reap(pids::Array{Int64, 1}, doable::Doable; callstyle=remotecall_fetch, returntype=Any)
    results = Dict{Int64, returntype}()
    todo = yieldfirst(doable) 
    @sync for pid in pids
        @async results[pid] = callstyle(Main.eval, pid, todo)
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


###  Manipulation utilities

function stitch(pids::Array{Int64,1}, expr_::Doable, cattype::Function)
    parts = reap(pids, expr_)
    reduce(cattype, [parts[k] for k in sort(collect(keys(parts)))])
end

function stitch(pid::Int64, expr_::Doable, cattype::Function)
    stitch([pid], expr_, cattype)
end

function stitch(pids::Array{Int64,1}, expr_::Doable)
    stitch(pids, expr_, vcat)
end

function stitch(pid::Int64, expr_::Doable)
    stitch([pid], expr_, vcat)
end

function stitch(expr_::Doable)
    pids = workers()
    stitch(pids, expr_, vcat)
end

# PERFMORMANCE TESTING

macro timeit(reps, expr)
   quote
       mean([@elapsed $expr for i in 1:$reps])
   end
end

function checksame(thing::Symbol)
    @assert length(Set(values(reap(thing))))==1
end

end
