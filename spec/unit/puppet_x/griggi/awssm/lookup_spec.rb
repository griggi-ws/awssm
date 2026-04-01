# frozen_string_literal: true

require 'spec_helper'

# Define AWS SDK mocks before loading the file that requires them
module Aws
  module SecretsManager
    class Client; end

    module Errors
      class ResourceNotFoundException < StandardError
        def initialize(context, message)
          super(message)
        end
      end

      class ServiceError < StandardError
        def initialize(context, message)
          super(message)
          @message = message
        end

        def message
          @message
        end
      end
    end
  end
end

# Temporarily stub require to handle AWS SDK gems
module Kernel
  alias_method :original_require, :require

  def require(name)
    if ['aws-sdk-core', 'aws-sdk-secretsmanager'].include?(name)
      true # Pretend the gem was loaded successfully
    else
      original_require(name)
    end
  end
end

require 'puppet_x/griggi/awssm/lookup'

# Restore the original require
module Kernel
  alias_method :require, :original_require
  remove_method :original_require
end

describe PuppetX::GRiggi::AWSSM::Lookup do
  let(:cache) { double('cache') }
  let(:cache_hash) { {} }
  let(:awssm_client) { double('Aws::SecretsManager::Client') }
  let(:secret_value) { 'super-secret-value' }
  let(:secret_id) { 'test/secret/key' }
  let(:region) { 'us-east-2' }

  before(:each) do
    allow(cache).to receive(:retrieve).with(described_class).and_return(cache_hash)
    allow(Aws::SecretsManager::Client).to receive(:new).and_return(awssm_client)
  end

  describe '.lookup' do
    context 'when secret is not cached' do
      it 'fetches secret from AWS and returns sensitive value' do
        response = double('response', to_h: { secret_string: secret_value })
        allow(awssm_client).to receive(:get_secret_value).and_return(response)

        result = described_class.lookup(
          cache: cache,
          id: secret_id,
          region: region
        )

        expect(result).to be_a(Puppet::Pops::Types::PSensitiveType::Sensitive)
        expect(result.unwrap).to eq(secret_value)
      end

      it 'stores the fetched secret in cache for future lookups' do
        response = double('response', to_h: { secret_string: secret_value })
        allow(awssm_client).to receive(:get_secret_value).and_return(response)

        described_class.lookup(
          cache: cache,
          id: secret_id,
          region: region
        )

        # Verify the secret was stored in cache
        cache_key = [secret_id, nil, region]
        expect(cache_hash[cache_key]).not_to be_nil
        expect(cache_hash[cache_key].unwrap).to eq(secret_value)
      end

      it 'uses the specified region' do
        response = double('response', to_h: { secret_string: secret_value })
        allow(awssm_client).to receive(:get_secret_value).and_return(response)

        expect(Aws::SecretsManager::Client).to receive(:new).with({ region: 'eu-west-1' }).and_return(awssm_client)

        described_class.lookup(
          cache: cache,
          id: secret_id,
          region: 'eu-west-1'
        )
      end

      it 'requests specific version when provided' do
        response = double('response', to_h: { secret_string: secret_value })
        version_id = 'version-123'

        expect(awssm_client).to receive(:get_secret_value).with({
                                                                   secret_id: secret_id,
                                                                   version_id: version_id
                                                                 }).and_return(response)

        described_class.lookup(
          cache: cache,
          id: secret_id,
          region: region,
          version: version_id
        )
      end
    end

    context 'when secret is cached' do
      let(:cached_data) { Puppet::Pops::Types::PSensitiveType::Sensitive.new(secret_value) }

      before(:each) do
        cache_hash[[secret_id, nil, region]] = cached_data
      end

      it 'returns cached value without calling AWS' do
        expect(awssm_client).not_to receive(:get_secret_value)

        result = described_class.lookup(
          cache: cache,
          id: secret_id,
          region: region
        )

        expect(result.unwrap).to eq(secret_value)
      end
    end

    context 'when ignore_cache is true' do
      let(:cached_data) { Puppet::Pops::Types::PSensitiveType::Sensitive.new('cached-value') }

      before(:each) do
        cache_hash[[secret_id, nil, region]] = cached_data
      end

      it 'fetches value from AWS even when cache exists' do
        response = double('response', to_h: { secret_string: secret_value })
        expect(awssm_client).to receive(:get_secret_value).and_return(response)

        result = described_class.lookup(
          cache: cache,
          id: secret_id,
          region: region,
          ignore_cache: true
        )

        expect(result.unwrap).to eq(secret_value)
      end
    end
  end

  describe '.get_secret' do
    context 'when secret exists with secret_string' do
      it 'returns the secret as a Sensitive value' do
        response = double('response', to_h: { secret_string: secret_value })
        allow(awssm_client).to receive(:get_secret_value).and_return(response)

        result = described_class.get_secret(
          id: secret_id,
          version: nil,
          region: region,
          create_options: {}
        )

        expect(result).to be_a(Puppet::Pops::Types::PSensitiveType::Sensitive)
        expect(result.unwrap).to eq(secret_value)
      end
    end

    context 'when secret exists with secret_binary' do
      let(:binary_value) { 'binary-secret-data' }

      it 'returns the binary secret as a Sensitive value' do
        response = double('response', to_h: { secret_binary: binary_value })
        allow(awssm_client).to receive(:get_secret_value).and_return(response)

        result = described_class.get_secret(
          id: secret_id,
          version: nil,
          region: region,
          create_options: {}
        )

        expect(result).to be_a(Puppet::Pops::Types::PSensitiveType::Sensitive)
        expect(result.unwrap).to eq(binary_value)
      end
    end

    context 'when secret does not exist' do
      context 'and create_missing is not enabled' do
        it 'raises a Puppet::Error' do
          allow(awssm_client).to receive(:get_secret_value)
            .and_raise(Aws::SecretsManager::Errors::ResourceNotFoundException.new('context', 'message'))

          expect do
            described_class.get_secret(
              id: secret_id,
              version: nil,
              region: region,
              create_options: {}
            )
          end.to raise_error(Puppet::Error, /No matching key.*and creating a missing secret is not enabled/)
        end
      end

      context 'and create_missing is enabled' do
        let(:create_options) do
          {
            'create_missing' => true,
            'password_length' => 16
          }
        end

        it 'creates a new secret' do
          allow(awssm_client).to receive(:get_secret_value)
            .and_raise(Aws::SecretsManager::Errors::ResourceNotFoundException.new('context', 'message'))

          random_password = double('random_password', random_password: 'generated-password')
          create_response = double('create_response', name: secret_id, arn: 'arn:aws:secretsmanager:...')

          expect(awssm_client).to receive(:get_random_password).and_return(random_password)
          expect(awssm_client).to receive(:create_secret).and_return(create_response)

          result = described_class.get_secret(
            id: secret_id,
            version: nil,
            region: region,
            create_options: create_options
          )

          expect(result).to be_a(Puppet::Pops::Types::PSensitiveType::Sensitive)
          expect(result.unwrap).to eq('generated-password')
        end
      end
    end

    context 'when AWS encounters a service error' do
      it 'raises a Puppet::Error with error details' do
        error = Aws::SecretsManager::Errors::ServiceError.new('context', 'Service unavailable')
        allow(awssm_client).to receive(:get_secret_value).and_raise(error)

        expect do
          described_class.get_secret(
            id: secret_id,
            version: nil,
            region: region,
            create_options: {}
          )
        end.to raise_error(Puppet::Error, /Non-specific error when looking up/)
      end
    end
  end

  describe '.create_secret' do
    let(:random_password) { 'randomly-generated-password' }
    let(:password_response) { double('password_response', random_password: random_password) }
    let(:create_response) { double('create_response', name: secret_id, arn: 'arn:aws:secretsmanager:...:secret:test/secret/key') }

    context 'with default options' do
      it 'creates a secret with default parameters' do
        expect(awssm_client).to receive(:get_random_password).with({
                                                                      password_length: 32,
                                                                      exclude_characters: '\'";\\{}@',
                                                                      exclude_numbers: false,
                                                                      exclude_punctuation: false,
                                                                      exclude_uppercase: false,
                                                                      exclude_lowercase: false,
                                                                      include_space: false,
                                                                      require_each_included_type: true
                                                                    }).and_return(password_response)

        expect(awssm_client).to receive(:create_secret).with({
                                                                description: 'Created by Puppet',
                                                                name: secret_id,
                                                                secret_string: random_password
                                                              }).and_return(create_response)

        result = described_class.create_secret(
          id: secret_id,
          region: region
        )

        expect(result).to be_a(Puppet::Pops::Types::PSensitiveType::Sensitive)
        expect(result.unwrap).to eq(random_password)
      end
    end

    context 'with custom options' do
      let(:options) do
        {
          'password_length' => 16,
          'exclude_characters' => '!@#',
          'exclude_numbers' => true,
          'description' => 'Custom description',
          'name' => 'custom/name'
        }
      end

      it 'creates a secret with custom parameters' do
        expect(awssm_client).to receive(:get_random_password).with(hash_including({
                                                                                     password_length: 16,
                                                                                     exclude_characters: '!@#',
                                                                                     exclude_numbers: true
                                                                                   })).and_return(password_response)

        expect(awssm_client).to receive(:create_secret).with({
                                                                description: 'Custom description',
                                                                name: 'custom/name',
                                                                secret_string: random_password
                                                              }).and_return(create_response)

        result = described_class.create_secret(
          id: secret_id,
          region: region,
          options: options
        )

        expect(result.unwrap).to eq(random_password)
      end
    end

    context 'when secret creation fails' do
      it 'raises a Puppet::Error on service error' do
        allow(awssm_client).to receive(:get_random_password).and_return(password_response)
        error = Aws::SecretsManager::Errors::ServiceError.new('context', 'Error creating secret')
        allow(awssm_client).to receive(:create_secret).and_raise(error)

        expect do
          described_class.create_secret(
            id: secret_id,
            region: region
          )
        end.to raise_error(Puppet::Error, /Non-specific error.*when creating/)
      end

      it 'raises a Puppet::Error when response is nil' do
        allow(awssm_client).to receive(:get_random_password).and_return(password_response)
        allow(awssm_client).to receive(:create_secret).and_return(nil)

        expect do
          described_class.create_secret(
            id: secret_id,
            region: region
          )
        end.to raise_error(Puppet::Error, /Invalid response when creating/)
      end
    end
  end
end
