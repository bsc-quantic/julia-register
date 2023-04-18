using Pkg
using Pkg: GitTools
using GitHub
using Registrator
using RegistryTools
using HTTP: URI
using LibGit2

# ARGS
# 1. inputs.registry
# 2. inputs.name
# 3. inputs.email
# 4. inputs.push
# 5. github.actor
registry, name, email, push, actor = ARGS
push = parse(Bool, push)

pkg_url = String(readchomp(`git remote get-url origin`))
@info "Repository = $pkg_url"

project = RegistryTools.Project("Project.toml")
isnothing(project) && error("Project file not found")
@info "Project" name = project.name UUID = project.uuid version = project.version

commit_hash = String(readchomp(`git rev-parse HEAD`))
tree_hash = String(readchomp(`git rev-parse HEAD^\{tree\}`))
@info "Hash" commit = commit_hash tree = tree_hash

const private_reg_url = GitTools.normalize_url(string(repo(registry).html_url))
const general_reg_url = "https://github.com/JuliaRegistries/General"

registry_repo = RegistryTools.get_registry(private_reg_url; force_reset=false)

const branch = get(ENV, "INPUTS_BRANCH", RegistryTools.registration_branch(project; url=pkg_url))

@info "Registry" url = private_reg_url path = registry_repo branch = branch

cd(mktempdir()) do
    # adapted from fregante/setup-git-user@v1, https://stackoverflow.com/a/71984173
    regbranch = RegistryTools.register(pkg_url, project, tree_hash;
        registry=private_reg_url,
        registry_deps=[general_reg_url],
        push=push,
        branch=branch,
        gitconfig=Dict(
            "user.name" => name,
            "user.email" => email,
            "url.$(string(URI(URI(private_reg_url); userinfo="$name:$(ENV["GITHUB_TOKEN"])"))).insteadOf" => private_reg_url
        ))
    @info "RegBranch = $regbranch"

    if haskey(regbranch.metadata, "error")
        if regbranch.metadata["kind"] == "New version" && regbranch.metadata["error"] == "Version $(project.version) already exists"
            println("::warning file=Project.toml,line=3,col=11,endColumn=$(11 + 1 + length(string(project.version))),title=Package not registered::Version $(project.version) already exists")
            return 0
        else
            println("::error file=Project.toml,title=$(regbranch.metadata["kind"])::$(regbranch.metadata["error"])")
            error(regbranch.metadata["error"])
        end
    end

    # open pull request
    params = Dict("base" => "master", "head" => branch, "maintainer_can_modify" => true)

    params["title"], params["body"] = Registrator.pull_request_contents(
        registration_type=get(regbranch.metadata, "kind", ""),
        package=project.name,
        repo=pkg_url,
        user=actor,
        version=project.version,
        commit=commit_hash,
        release_notes="",
    )
    @info "Pull Request contents" title = params["title"] body = params["body"]

    auth = GitHub.authenticate(ENV["GITHUB_TOKEN"])
    pr = GitHub.create_pull_request(registry, auth=auth, params=params)
    GitHub.add_labels(repo, pr, lowercase.(regbranch.metadata["labels"]), auth=auth)
end

open(ENV["GITHUB_OUTPUT"], "w") do io
    println(io, "name=$(project.name)")
    println(io, "uuid=$(project.uuid)")
    println(io, "version=$(project.version)")
    println(io, "hash=$tree_hash")
    println(io, "branch=$branch")
    println(io, "path=$(LibGit2.path(registry_repo))")
end

open(ENV["GITHUB_STEP_SUMMARY"], "w") do io
    println(
        io,
        """
        # Package registered :package:

        - Registry: $private_reg_url
        - Project: $(project.name)
        - UUID: $(project.uuid)
        - Version: $(project.version)
        """
    )
end
