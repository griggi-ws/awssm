# frozen_string_literal: true

require_relative '../../../puppet_x/griggi/awssm/lookup'
begin
  require 'aws-sdk-core'
rescue LoadError
  raise Puppet::DataBinding::LookupError, '[AWSSM]: Must install aws-sdk-secretsmanager gem on both agent and server ruby versions to use awssm_lookup'
end

Puppet::Functions.create_function(:'awssm::lookup', Puppet::Functions::InternalFunction) do

  dispatch :lookup do
    cache_param # Completely undocumented feature that I can only find implemented in a single official Puppet module? Sure why not let's try it
    param 'String', :id
    optional_param 'String', :version
    optional_param 'Optional[String]', :region
    optional_param 'Optional[Number]', :cache_stale
    optional_param 'Optional[Boolean]', :ignore_cache
    optional_param 'Optional[Hash]', :create_options
    return_type 'Sensitive'
  end

  # Allows for passing a hash of options to the vault_lookup::lookup() function.
  #
  # @example
  #  $foo = awssm::lookup('secret/some/path/foo',
  #    { 'version' => 'AWSPREVIOUS', 'region' => 'us-east-1' }
  #  )
  #
  dispatch :lookup_opts_hash do
    cache_param
    param 'String[1]', :id
    param 'Hash[String[1], Data]', :options
    return_type 'Sensitive'
  end

  # Lookup with a path and an options hash. The use of undef/nil in positional parameters with a deferred call appears to not work, so we need this.
  # Be sure to also update the default values in the awssm::lookup function, as those will be used in the case that an options hash is passed without
  # all values defined.
  def lookup_opts_hash(cache, id, options = { 'region' => nil,
                                              'version' => 'AWSCURRENT',
                                              'cache_stale' => 30,
                                              'ignore_cache' => false,
                                              'create_options' => {
                                                'create_missing' => true,
                                                'password_length' => 32,
                                                'exclude_characters' => '\'";\\{}@',
                                                'exclude_numbers' => false,
                                                'exclude_punctuation' => false,
                                                'exclude_uppercase' => false,
                                                'exclude_lowercase' => false,
                                                'include_space' => false,
                                                'require_each_included_type' => true
                                              }, })

    region_lookup = [closure_scope['trusted']['extensions']['pp_region'], closure_scope['facts']['region'], call_function('lookup', 'region', nil, nil, 'us-east-2')]
    begin
      ec2_metadata = Aws::EC2Metadata.new
      host_region = ec2_metadata.get('/latest/meta-data/placement/region')
      region_lookup.unshift(host_region)
      Puppet.info "[AWSSM]: EC2 metadata lookup successful, host region #{host_region}"
      Puppet.info "[AWSSM]: region_lookup new value: #{region_lookup}"
    rescue => e
      Puppet.info "[AWSSM]: EC2 metadata inaccessible, error #{e}"
    end

    # Things we don't want to be `nil` if not passed in the initial call
    options['region'] ||= region_lookup.compact.first
    options['cache_stale'] ||= 30
    options['ignore_cache'] ||= false
    # NOTE: The order of these options MUST be the same as the lookup()
    # function's signature. If new parameters are added to lookup(), or if the
    # order of existing parameters change, those changes must also be made
    # here.
    
    Puppet.debug "[AWSSM]: Calling lookup function in region #{region}"
    PuppetX::GRiggi::AWSSM::Lookup.lookup(cache: cache,
                                          id: id,
                                          region: options['region'],
                                          version: options['version'],
                                          cache_stale: options['cache_stale'],
                                          ignore_cache: options['ignore_cache'],
                                          create_options: options['create_options'])
  end

  # Lookup with a path and positional arguments.
  # NOTE: If new parameters are added, or if the order of existing parameters
  # change, those changes must also be made to the lookup() call in
  # lookup_opts_hash().
  def lookup(cache,
             id,
             region = nil,
             version = nil,
             cache_stale = 30,
             ignore_cache = false,
             create_options = {
               'create_missing' => true,
               'password_length' => 32,
               'exclude_characters' => '\'";\\{}@',
               'exclude_numbers' => false,
               'exclude_punctuation' => false,
               'exclude_uppercase' => false,
               'exclude_lowercase' => false,
               'include_space' => false,
               'require_each_included_type' => true
             })

    region_lookup = [closure_scope['trusted']['extensions']['pp_region'], closure_scope['facts']['region'], call_function('lookup', 'region', nil, nil, 'us-east-2')]
    begin
      ec2_metadata = Aws::EC2Metadata.new
      host_region = ec2_metadata.get('/latest/meta-data/placement/region')
      region_lookup.unshift(host_region)
      Puppet.info "[AWSSM]: EC2 metadata lookup successful, host region #{host_region}"
      Puppet.info "[AWSSM]: region_lookup new value: #{region_lookup}"
    rescue => e
      Puppet.info "[AWSSM]: EC2 metadata inaccessible, error #{e}"
    end

    region ||= region_lookup.compact.first
    Puppet.debug "[AWSSM]: Calling lookup function in region #{region}"

    PuppetX::GRiggi::AWSSM::Lookup.lookup(cache: cache,
                                          id: id,
                                          region: region,
                                          version: version,
                                          cache_stale: cache_stale,
                                          ignore_cache: ignore_cache,
                                          create_options: create_options)
  end
end
