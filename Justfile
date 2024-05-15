#!/usr/bin/env just --justfile
# Documentation: https://just.systems/man/en/

set shell := ['nu', '-c']

# Print this help
default:
    @just -l

# Format Justfile
format:
    @just --fmt --unstable

# Install git commit hooks
githooks:
    #!/usr/bin/env nu
    $env.config = { use_ansi_coloring: false, error_style: "plain" }
    let hooks_folder = '.githooks'
    if (git config core.hooksPath) != $hooks_folder {
      print 'Installing git commit hooks'
      git config core.hooksPath $hooks_folder
      # npm install -g @commitlint/config-conventional
    }
    if not ($hooks_folder | path exists) {
      mkdir $hooks_folder
      "#!/usr/bin/env -S sh\nset -eu\njust test" | save $"($hooks_folder)/pre-commit"
      chmod 755 $"($hooks_folder)/pre-commit"
      "#!/usr/bin/env -S sh\nset -eu\n\nMSG_FILE=\"$1\"\nPATTERN='^(fix|feat|docs|style|chore|test|refactor|ci|build)(\\([a-z0-9/-]+\\))?!?: [a-z].+$'\n\nif ! head -n 1 \"${MSG_FILE}\" | grep -qE \"${PATTERN}\"; then\n\techo \"Your commit message:\" 1>&2\n\tcat \"${MSG_FILE}\" 1>&2\n\techo 1>&2\n\techo \"The commit message must conform to this pattern: ${PATTERN}\" 1>&2\n\techo \"Contents:\" 1>&2\n\techo \"- follow the conventional commits style (https://www.conventionalcommits.org/)\" 1>&2\n\techo 1>&2\n\techo \"Example:\" 1>&2\n\techo \"feat: add super awesome feature\" 1>&2\n\texit 1\nfi"| save $"($hooks_folder)/commit-msg"
      chmod 755 $"($hooks_folder)/commit-msg"
      # if not (".commitlintrc.yaml" | path exists) {
      # "extends:\n  - '@commitlint/config-conventional'" | save ".commitlintrc.yaml"
      # }
      # git add $hooks_folder ".commitlintrc.yaml"
      git add $hooks_folder
    }

# Build image
build: githooks
    #!/usr/bin/env nu
    let package = (open package.json)
    let image = $"($package.registry)/($package.name):($package.version)"
    print -e $"Building image ($image)"
    nix build

# Load image locally
load: build
    #!/usr/bin/env nu
    ./result | docker image load

# Run image locally
run: load
    #!/usr/bin/env nu
    let package = (open package.json)
    let image = $"($package.registry)/($package.name):($package.version)"
    docker run --name $package.name -it --rm $image

# Run shell image locally
run-sh: load
    #!/usr/bin/env nu
    let package = (open package.json)
    let image = $"($package.registry)/($package.name):($package.version)"
    docker run --name $package.name -it --rm --entrypoint /bin/sh $image --

# Inspect image
inspect: build
    #!/usr/bin/env nu
    let package = (open package.json)
    let image = {
      RepoTags: [$"($package.registry)/($package.name):($package.version)"],
    }
    ./result | skopeo inspect --config docker-archive:/dev/stdin  | from json | merge $image

# Push image
push:
    #!/usr/bin/env nu
    let package = (open package.json)
    let image = $"($package.registry)/($package.name):($package.version)"
    ./result | skopeo copy docker-archive:/dev/stdin $"docker://($image)"

# Create a new release of this module. LEVEL can be one of: major, minor, patch, premajor, preminor, prepatch, or prerelease.
release LEVEL="patch" NEW_VERSION="":
    #!/usr/bin/env nu
    if (git rev-parse --abbrev-ref HEAD) != "main" {
      print -e "ERROR: A new release can only be created on the main branch."
      exit 1
    }
    if (git status --porcelain | wc -l) != "0" {
      print -e "ERROR: Repository contains uncommited changes."
      exit 1
    }
    # str replace -r "-.*" "" - strips git's automatic prerelease version
    let package = (open package.json)
    # let current_version = (git describe | str replace -r "-.*" "" | deno run npm:semver $in)
    let current_version = ($package.version |  deno run npm:semver $in)
    let new_version = if "{{ NEW_VERSION }}" == "" {$current_version | deno run npm:semver -i "{{ LEVEL }}" $in | lines | get 0} else {"{{ NEW_VERSION }}"}
    print "\nChangelog:\n"
    git cliff --strip all -u -t $new_version
    input -s $"Version will be bumped from ($current_version) to ($new_version)\nPress enter to confirm.\n"
    open package.json | upsert version $new_version | save -f package.json; git add package.json
    git cliff -t $new_version -o CHANGELOG.md; git add CHANGELOG.md
    git commit -n -m $"Bump version to ($new_version)"
    just build
    just push
    git tag -s -m $new_version $new_version
    git push --atomic origin refs/heads/main $"refs/tags/($new_version)"
    git cliff --strip all --current | gh release create -F - $new_version

# Clean files
clean: githooks
    rm -pf result
