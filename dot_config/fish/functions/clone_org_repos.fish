function clone_org_repos
    if test (count $argv) -lt 1
        echo "Usage: clone_org_repos ORGANIZATION_NAME"
        return 1
    end

    set org_name $argv[1]
    set output_dir $org_name

    if not test -d "$output_dir"
        mkdir -p "$output_dir"
        echo "Created directory: $output_dir"
    end

    cd "$output_dir" || return 1

    set api_url "https://api.github.com/orgs/$org_name/repos?per_page=100"
    set page_num 1
    set total_repos 0

    while true
        echo "Fetching page $page_num of repositories..."

        set curl_cmd "curl -s -H 'Accept: application/vnd.github+json'"
        if set -q GITHUB_TOKEN
            set curl_cmd "$curl_cmd -H 'Authorization: token $GITHUB_TOKEN'"
        end
        set curl_cmd "$curl_cmd '$api_url'"

        set repos_json (eval $curl_cmd)

        if test -z "$repos_json" || string match -q '*"message"*' -- $repos_json
            set error_msg (echo $repos_json | jq -r '.message' 2>/dev/null || echo "Unknown error")
            echo "Error fetching repositories: $error_msg"
            cd -
            return 1
        end

        set repos (echo $repos_json | jq -r '.[] | .clone_url' 2>/dev/null)
        set repo_count (count $repos)

        if test $repo_count -eq 0
            break
        end

        for repo in $repos
            set repo_name (basename $repo .git)
            echo "Cloning: $repo_name"

            if test -d "$repo_name"
                echo "Directory $repo_name already exists, skipping."
            else
                git clone $repo >/dev/null 2>&1
                if test $status -eq 0
                    echo "Successfully cloned $repo_name"
                    set total_repos (math $total_repos + 1)
                else
                    echo "Failed to clone $repo_name"
                end
            end
        end

        set next_url (eval "$curl_cmd -I" | grep -i "link:" | grep -o '<[^>]*>; rel="next"' | cut -d'<' -f2 | cut -d'>' -f1)

        if test -z "$next_url"
            break
        end

        set api_url "$next_url"
        set page_num (math $page_num + 1)
    end

    echo "Completed cloning $total_repos repositories from $org_name into $output_dir"
    cd -
end

function __fish_suggest_github_orgs
    if not set -q GITHUB_TOKEN
        return 1
    end

    set -l query (commandline -t | string trim)

    if test -n "$query" -a (string length "$query") -ge 2
        set curl_cmd "curl -s -H 'Accept: application/vnd.github+json' -H 'Authorization: token $GITHUB_TOKEN'"
        set search_url "https://api.github.com/search/users?q=$query+type:org&per_page=10"

        set orgs_json (eval "$curl_cmd '$search_url'")

        if test $status -eq 0 -a -n "$orgs_json"
            echo $orgs_json | jq -r '.items[].login' 2>/dev/null | grep -v '^null$' | sort -u
        end
    end
end

# Completions
complete -c clone_org_repos -f -a "(__fish_suggest_github_orgs)" -d "GitHub organization"
