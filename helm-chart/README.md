# Munki File Server Helm Chart

This Helm chart deploys both an SFTP file server and an NGINX web server for serving Munki repository files. Both services share the same persistent volume with 20GB of local-path storage.

## Prerequisites

- Kubernetes cluster 1.19+
- Helm 3.0+
- Local-path provisioner installed (for local-path storage class)

## Installation

```bash
# Install with default values
helm install munki-fileserver ./helm-chart

# Install with custom values
helm install munki-fileserver ./helm-chart -f custom-values.yaml

# Upgrade existing installation
helm upgrade munki-fileserver ./helm-chart
```

## Configuration

### Storage

The chart creates a PersistentVolumeClaim with:
- Size: 20Gi (configurable via `storage.size`)
- Storage Class: `local-path` (configurable via `storage.storageClass`)
- Access Mode: `ReadWriteOnce` (local-path limitation - both pods use pod affinity to schedule on the same node)

### SFTP Server

The SFTP server uses the `atmoz/sftp` image and is configured with:
- Default user: `munki` (username and password can be changed in values.yaml)
- Port: 22 (configurable)
- Service Type: ClusterIP (configurable)

### NGINX Server

The NGINX server uses the official `nginx:alpine` image and:
- Serves files from the shared volume
- Enables directory listing
- Port: 80 (configurable)
- Service Type: ClusterIP (configurable)

## Usage

### Accessing SFTP

Once deployed, you can access the SFTP server using:
```bash
# From within the cluster
sftp munki@<service-name>-sftp:<port>

# Or port-forward to access from outside
kubectl port-forward svc/<release-name>-munki-fileserver-sftp 2222:22
sftp -P 2222 munki@localhost
```

Default credentials (change these!):
- Username: `munki`
- Password: `changeme123`

### Accessing NGINX

```bash
# Port-forward to access from outside
kubectl port-forward svc/<release-name>-munki-fileserver-nginx 8080:80

# Then access via browser or curl
curl http://localhost:8080
```

## Customization

Edit `values.yaml` or create a custom values file:

```yaml
storage:
  size: 20Gi
  storageClass: local-path

sftp:
  users:
    - name: myuser
      password: securepassword
      uid: 1000
      gid: 1000

nginx:
  service:
    type: LoadBalancer  # For external access
    port: 80
```

## Security Considerations

⚠️ **Important**: The default SFTP password is `changeme123`. Change this before deploying to production!

You can:
1. Update `values.yaml` with a secure password
2. Use Kubernetes Secrets (modify templates to add secret support)
3. Set up proper authentication and authorization

## Troubleshooting

### VolumeBinding Errors

If you encounter errors like "Operation cannot be fulfilled on persistentvolumeclaims", try:

1. Delete any existing PVC in a pending or error state:
```bash
kubectl delete pvc <release-name>-munki-fileserver-storage
```

2. Reinstall the chart:
```bash
helm uninstall munki-fileserver
helm install munki-fileserver ./helm-chart
```

3. Verify the PVC is bound:
```bash
kubectl get pvc
kubectl describe pvc <release-name>-munki-fileserver-storage
```

**Note**: The `local-path` storage class uses `WaitForFirstConsumer` binding mode, meaning the PVC won't bind until a pod that uses it is scheduled. The first pod will bind the volume to its node, and the second pod will be scheduled on the same node via pod affinity.

## Uninstallation

```bash
helm uninstall munki-fileserver
```

**Note**: Uninstalling will delete the deployments and services, but the PersistentVolumeClaim will remain to preserve data (due to `helm.sh/resource-policy: keep` annotation). Delete it manually if you want to remove the storage:

```bash
kubectl delete pvc <release-name>-munki-fileserver-storage
```

