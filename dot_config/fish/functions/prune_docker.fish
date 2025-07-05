function prune_docker -d "Toggle between different fish prompt styles"
    docker system prune -a --volumes -f && docker builder prune -a -f
end
