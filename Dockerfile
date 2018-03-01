FROM quay.io/getpantheon/gcloud-kubectl:392

RUN mkdir /cleanup
ADD delete-orphaned-kube-network-load-balancers.sh /cleanup/
add lib  /cleanup/lib
ADD docker-run.sh  /
RUN chmod 755 /docker-run.sh

CMD ["./docker-run.sh"]
