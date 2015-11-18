
# Descibing network topology

@everywhere using ClusterUtils

describepids() 

describepids(remote=1)

describepids(remote=2)

describepids(procs(); filterfn=(x)->ismatch(r"tesla", x)) #filter based on `hostname`


# Binding variables to names on remotes

@everywhere using ClusterUtils

@fetchfrom remotes[2] bobisuncle

sendtoall(:bobisuncle, pi^2)

@fetchfrom remotes[2] bobisuncle

bobisuncle





# Example 1 - Using a MessageDict to aggregate work on master

@everywhere using ClusterUtils

remotes = workers()

msgmaster = MessageDict(remotes, randn(3))

msgnameonremotes = :msgremote

distribute(msgnameonremotes, msgmaster)

[@spawnat k msgremote[k] = randn(3) for k in remotes]

remotecall_fetch(eval, remotes[1], msgnameonremotes)

collectmsgsatmaster(msgnameonremotes, msgmaster)



# Example 2 - Using MessageDict purely remotely to swap messages between processes

@everywhere using ClusterUtils

remotes = workers()

sendtopids(remotes, :somemsg, MessageDict() )

isdefined(:somemsg)

@fetchfrom remotes[1] somemsg

[@spawnat k somemsg[k] = 2k for k in remotes]

@fetchfrom remotes[1] somemsg

swapmsgs(remotes, :somemsg)

@fetchfrom remotes[1] somemsg

ClusterUtils.@timeit 100 swapmsgs( workers(), :somemsg )





