FROM quay.io/getpantheon/gcloud-kubectl:233

ADD delete-orphaned-kube-network-load-balancers.sh /
ADD docker-run.sh  /
RUN chmod 755 /docker-run.sh

CMD ["./docker-run.sh"]
