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
println("::info::Repository = $pkg_url")

project = RegistryTools.Project("Project.toml")
isnothing(project) && error("Project file not found")
println("::info::Project name = $(project.name)")
println("::info::Project UUID = $(project.uuid)")
println("::info::Project version = $(project.version)")

commit_hash = String(readchomp(`git rev-parse HEAD`))
println("::info::Commit hash = $commit_hash")

tree_hash = String(readchomp(`git rev-parse HEAD^\{tree\}`))
println("::info::Tree hash = $tree_hash")

const private_reg_url = GitTools.normalize_url(string(repo(registry).html_url))
const general_reg_url = "https://github.com/JuliaRegistries/General"
println("::info::Registry = $private_reg_url")

registry_repo = RegistryTools.get_registry(private_reg_url; force_reset=false)
println("::info::Registry path = $registry_repo")

const branch = get(ENV, "INPUTS_BRANCH", RegistryTools.registration_branch(project; url=pkg_url))
println("::info::Registry branch = $branch")

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
    println("::info::RegBranch = $regbranch")

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
    title, body = Registrator.pull_request_contents(
        registration_type=get(regbranch.metadata, "kind", ""),
        package=project.name,
        repo=pkg_url,
        user=actor,
        version=project.version,
        commit=commit_hash,
        release_notes="",
    )

    pr = GitHub.create_pull_request(
        registry;
        title=title,
        body=body,
        head=branch,
        base="master"
    )

    GitHub.add_labels(repo, pr, lowercase.(regbranch.metadata["labels"]))
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
