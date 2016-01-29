input {
    zeromq {
        topology => "pubsub"
        mode => "client"
        topic => "SERVICE_ID"
        type => "SERVICE_NAME"
        address => ["ZMQ_IP"]
    }
}
