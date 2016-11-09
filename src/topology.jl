
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




