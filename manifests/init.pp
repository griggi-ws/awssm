# Installs dependencies for awssm functions
class awssm {
  stdlib::ensure_packages(['aws-sdk-secretsmanager'], { provider => 'puppet_gem' })
}
