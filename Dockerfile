FROM quay.io/getpantheon/gcloud-kubectl:master


ADD delete-orphaned-kube-network-load-balancers.sh /
ADD docker-run.sh  /

CMD ["/docker-run.sh"]
