---
layout: ../layouts/GistLayout.astro
tags: [kubernetes]
---

# CKA - notes

General

- Define the dry run flags as env variable: `DR=” - dry-run=client -o yaml”` and use it as follows: `k run nginx --image=nginx $DR`
- Indent in VIM using: `>>` . If you want to indent `4` lines: `4>>`
- To delete a pod quickly user `--force` : `k delete po my-po --force`

Cluster Maintenance

- To empty a node of all applications and mark it unschedulable: `k drain node01 --ignore-daemonsets`
- To make node schedulable again: `k uncordon node01`
- To find taints on a node: `k describe no controlplane | grep -i taints`
- When a pod that is not part of a replicaset is running on a node, node draining won’t work. To make it work, use `--force`: `k drain node01 --ignore-daemonsets --force`
    
    To keep such pods running so that they are not lost forever, `cordon` the node instead of `drain`: `k cordon node01`. This will ensure that no new pods are scheduled on this node and the existing pods will not be affected by this operation.
    
- Find latest version available for upgrade using current version of `kubeadm` : `kubeadm upgrade plan`
- Actual upgrade process:
    
    For `controlplane`
    
    - 
        
        ```
        To seamlessly transition from Kubernetes v1.28 to v1.29 and gain access to the packages specific to the desired Kubernetes minor version, follow these essential steps during the upgrade process. This ensures that your environment is appropriately configured and aligned with the features and improvements introduced in Kubernetes v1.29.
        
        On the controlplane node:
        
        Use any text editor you prefer to open the file that defines the Kubernetes apt repository.
        
        vim /etc/apt/sources.list.d/kubernetes.list
        Update the version in the URL to the next available minor release, i.e v1.29.
        
        deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /
        After making changes, save the file and exit from your text editor. Proceed with the next instruction.
        
        root@controlplane:~# apt update
        root@controlplane:~# apt-cache madison kubeadm
        Based on the version information displayed by apt-cache madison, it indicates that for Kubernetes version 1.29.0, the available package version is 1.29.0-1.1. Therefore, to install kubeadm for Kubernetes v1.29.0, use the following command:
        
        root@controlplane:~# apt-get install kubeadm=1.29.0-1.1
        Run the following command to upgrade the Kubernetes cluster.
        
        root@controlplane:~# kubeadm upgrade plan v1.29.0
        root@controlplane:~# kubeadm upgrade apply v1.29.0
        Note that the above steps can take a few minutes to complete.
        
        Now, upgrade the version and restart Kubelet. Also, mark the node (in this case, the "controlplane" node) as schedulable.
        
        root@controlplane:~# apt-get install kubelet=1.29.0-1.1
        root@controlplane:~# systemctl daemon-reload
        root@controlplane:~# systemctl restart kubelet
        root@controlplane:~# kubectl uncordon controlplane
        ```
        
    
    for `node01`
    
    - 
        
        ```
        On the node01 node, run the following commands:
        
        If you are on the controlplane node, run ssh node01 to log in to the node01.
        
        Use any text editor you prefer to open the file that defines the Kubernetes apt repository.
        
        vim /etc/apt/sources.list.d/kubernetes.list
        Update the version in the URL to the next available minor release, i.e v1.29.
        
        deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /
        After making changes, save the file and exit from your text editor. Proceed with the next instruction.
        
        root@node01:~# apt update
        root@node01:~# apt-cache madison kubeadm
        Based on the version information displayed by apt-cache madison, it indicates that for Kubernetes version 1.29.0, the available package version is 1.29.0-1.1. Therefore, to install kubeadm for Kubernetes v1.29.0, use the following command:
        
        root@node01:~# apt-get install kubeadm=1.29.0-1.1
        # Upgrade the node 
        root@node01:~# kubeadm upgrade node
        Now, upgrade the version and restart Kubelet.
        
        root@node01:~# apt-get install kubelet=1.29.0-1.1
        root@node01:~# systemctl daemon-reload
        root@node01:~# systemctl restart kubelet
        Type exit or logout or enter CTRL + d to go back to the controlplane node.
        ```
        
- Find out address can you reach the ETCD cluster from the controlplane node: `kubectl describe pod etcd-controlplane -n kube-system` and look for `--listen-client-urls`
- Save etcd snapshot to particular location: `ETCDCTL_API=3 etcdctl --endpoints=https://[127.0.0.1]:2379 \
--cacert=/etc/kubernetes/pki/etcd/ca.crt \
--cert=/etc/kubernetes/pki/etcd/server.crt \
--key=/etc/kubernetes/pki/etcd/server.key \
snapshot save /opt/snapshot-pre-boot.db`
- Restore etcd backup and update cluster:
    - 
        
        ```
        First Restore the snapshot:
        
        root@controlplane:~# ETCDCTL_API=3 etcdctl  --data-dir /var/lib/etcd-from-backup \
        snapshot restore /opt/snapshot-pre-boot.db
        
        2022-03-25 09:19:27.175043 I | mvcc: restore compact to 2552
        2022-03-25 09:19:27.266709 I | etcdserver/membership: added member 8e9e05c52164694d [http://localhost:2380] to cluster cdf818194e3a8c32
        root@controlplane:~# 
        
        Note: In this case, we are restoring the snapshot to a different directory but in the same server where we took the backup (the controlplane node) As a result, the only required option for the restore command is the --data-dir.
        
        Next, update the /etc/kubernetes/manifests/etcd.yaml:
        
        We have now restored the etcd snapshot to a new path on the controlplane - /var/lib/etcd-from-backup, so, the only change to be made in the YAML file, is to change the hostPath for the volume called etcd-data from old directory (/var/lib/etcd) to the new directory (/var/lib/etcd-from-backup).
        
          volumes:
          - hostPath:
              path: /var/lib/etcd-from-backup
              type: DirectoryOrCreate
            name: etcd-data
        With this change, /var/lib/etcd on the container points to /var/lib/etcd-from-backup on the controlplane (which is what we want).
        
        When this file is updated, the ETCD pod is automatically re-created as this is a static pod placed under the /etc/kubernetes/manifests directory.
        
        Note 1: As the ETCD pod has changed it will automatically restart, and also kube-controller-manager and kube-scheduler. Wait 1-2 to mins for this pods to restart. You can run the command: watch "crictl ps | grep etcd" to see when the ETCD pod is restarted.
        
        Note 2: If the etcd pod is not getting Ready 1/1, then restart it by kubectl delete pod -n kube-system etcd-controlplane and wait 1 minute.
        
        Note 3: This is the simplest way to make sure that ETCD uses the restored data after the ETCD pod is recreated. You don't have to change anything else.
        
        If you do change --data-dir to /var/lib/etcd-from-backup in the ETCD YAML file, make sure that the volumeMounts for etcd-data is updated as well, with the mountPath pointing to /var/lib/etcd-from-backup (THIS COMPLETE STEP IS OPTIONAL AND NEED NOT BE DONE FOR COMPLETING THE RESTORE)
        ```
        
- Get number of nodes that are part of ETCD cluster: `ETCDCTL_API=3 etcdctl \
--endpoints=https://127.0.0.1:2379 \
--cacert=/etc/etcd/pki/ca.pem \
--cert=/etc/etcd/pki/etcd.pem \
--key=/etc/etcd/pki/etcd-key.pem \
member list`
- How to get necessary values for the `etcd` commands:
    - Get client url: `k describe po -n kube-system etcd-cluster1-controlplane | grep advertise-client-urls`
        
        Result: `--advertise-client-urls=https://192.48.29.3:2379`
        
    - Get PKI info: `k describe po -n kube-system etcd-cluster1-controlplane | grep pki`
        
        Result: `--cert-file=/etc/kubernetes/pki/etcd/server.crt
        --key-file=/etc/kubernetes/pki/etcd/server.key
        --peer-cert-file=/etc/kubernetes/pki/etcd/peer.crt
        --peer-key-file=/etc/kubernetes/pki/etcd/peer.key
        --peer-trusted-ca-file=/etc/kubernetes/pki/etcd/ca.crt
        --trusted-ca-file=/etc/kubernetes/pki/etcd/ca.crt
        /etc/kubernetes/pki/etcd from etcd-certs (rw)
        Path: /etc/kubernetes/pki/etcd`
        
    - SSH into the control plane node: `ssh cluster1-controlplane`
    - Take backup: `ETCDCTL_API=3 etcdctl --endpoints=<advertise-client-urls-VALUE> --cacert=<--trusted-ca-file-VALUE> --cert=<<--cert-file-VALUE>> --key=<--key-file-VALUE> snapshot save <FILE>`
- For external ETCD server, restore using the restore command and
    - update the systemd service unit file for `etcd`by running `vi /etc/systemd/system/etcd.service` and add the new value for `data-dir`
    - Set correct permissions to new directory: `chown -R etcd:etcd /var/lib/etcd-data-new`
    - Finally, reload and restart service: `systemctl daemon-reload && systemctl restart etcd`

Security

- Get cert details: `openssl x509 -in <file-path.crt> -text -noout`
- Getting logs of containers: identify the container using `crictl ps -a` and then use `crictl logs container-id`
- To get base64 output in one line which is useful when base64 encoding the csr string which has newlines: `base64 -w 0 <CSR_FILE>`
- While creating `clusterrole` , we can specify multiple resources at once. For example: `k create clusterrole storage-admin --resource=persistentvolumes,storageclasses --verb=get,list,watch,create,delete`
- Check if a user can carry out certain operation: `k --as=<user> <OPERATION>` for example: `k --as=test-user get no`

Storage

- To replace an existing resource: `k replace -f <YAML_FILE> --force`

Networking

- Getting network interface configured for cluster connectivity on the `controlplane` node:
    - Run: `kubectl get nodes -o wide` to see the IP address assigned to the `controlplane` node.
    - Get the network interface using: `ip a | grep -B2 <IP>`
- Get MAC address for a network interface: `ip link show <INTERFACE>`
- Find network range are the nodes in the cluster part of: `ip addr` and look at the IP address assigned to the `eth0` interfaces. Derive network range from that.
- Get IP address of default gateway: `ip route show default`
- See the network interface created by CNI plugin: `ip link`
- Find IP address range of a network interface (for example, `weave`) : `ip addr show weave`
- List ports listening: `netstat -nplt`
- Count client connections on ports (for example, etcd running on 2379): `netstat -anp | grep etcd | grep 2379 | wc -l`
- Identify container runtime endpoint: `ps -aux | grep kubelet | grep --color container-runtime-endpoint`
- path configured with all binaries of CNI supported plugins: `/opt/cni/bin`
- Find CNI plugin configured to be used on this kubernetes cluster: `ls /etc/cni/net.d/`
- Find binary executable file will be run by kubelet after a container and its associated namespace are created: Look at the `type` field in file `/etc/cni/net.d/10-flannel.conflist`
- Find the range of IP addresses configured for PODs on this cluster: Find the CNI plugin by getting pods in the `kube-system` namespace. Suppose it’s `weave` , check the pod logs and look for `ipalloc-range`: `k logs <weave-pod-name> -n kube-system | grep ipalloc-range`
- Find P Range configured for the services within the cluster: `cat /etc/kubernetes/manifests/kube-apiserver.yaml   | grep cluster-ip-range`

Troubleshooting

- **Worker node failures** - here is the general debugging workflow
    - Find the node that’s not ready from `controlplane` :  `k get no`
    - check the status of node from `controlplane` : `k describe no <NOT_READY_NODE>`
    - ssh into the node, check with `service kubelet status`
    - run `journalctl -u kubelet -f`   to see the logs
    - start the service if stopped `service kubelet start` or if it’s running but in impaired state, restart: `service kubelet restart`
    - On nodes
        - Kubelet service config is stored in `/var/lib/kubelet/config.yaml`
        - the `kubeconfig` used by `kubelet` on nodes is stored in `/etc/kubernetes/kubelet.conf. controlplane` port number for nodes to connect is `6443` and it’s configured in the `kubeconfig` file.
