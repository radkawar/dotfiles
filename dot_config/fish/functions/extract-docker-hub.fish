function extract-docker-hub
    if test (count $argv) -lt 1
        echo "Usage: extract-docker-hub image [tag]"
        return 1
    end

    set -l image_name $argv[1]

    set -l image_tag latest
    if test (count $argv) -gt 1
        set image_tag $argv[2]
    end

    set -l full_image "$image_name:$image_tag"
    set -l dir_name (string replace -a '/' '-' $image_name)-$image_tag

    echo "Pulling $full_image..."
    docker pull $full_image

    if test $status -ne 0
        echo "Failed to pull image $full_image"
        return 1
    end

    echo "Creating temporary container..."
    set -l container_id (docker create --entrypoint /bin/sh $full_image -c "exit 0")

    if test -z "$container_id"
        set container_id (docker create $full_image /bin/true 2>/dev/null)

        if test -z "$container_id"
            set container_id (docker create $full_image 2>/dev/null)

            if test -z "$container_id"
                echo "Failed to create container from $full_image"
                return 1
            end
        end
    end

    echo "Creating directory $dir_name..."
    mkdir -p $dir_name

    echo "Exporting and extracting file system..."
    docker export $container_id | tar -x -C $dir_name

    echo "Removing temporary container..."
    docker rm $container_id

    echo "Done. File system extracted to $dir_name"
end

function __extract_docker_hub_get_images
    docker images --format "{{.Repository}}"
end

function __extract_docker_hub_get_tags
    set -l image $argv[1]
    if test -n "$image"
        docker images --format "{{if eq .Repository \"$image\"}}{{.Tag}}{{end}}" | grep -v '^$'
    end
end

complete -c extract-docker-hub -f
complete -c extract-docker-hub -n "test (count (commandline -opc)) -eq 1" -a "(__extract_docker_hub_get_images)" -d "Docker Image"
complete -c extract-docker-hub -n "test (count (commandline -opc)) -eq 2" -a "(__extract_docker_hub_get_tags (commandline -opc)[2])" -d "Image Tag"
