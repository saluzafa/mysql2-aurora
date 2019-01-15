RSpec.describe Mysql2::Aurora::Client do
  let :client do
    Mysql2::Client.new(
      host:             ENV['TEST_DB_HOST'],
      username:         ENV['TEST_DB_USER'],
      password:         ENV['TEST_DB_PASS'],
      aurora_max_retry: 2
    )
  end

  describe 'Mysql2::Aurora::VERSION' do
    subject do
      Mysql2::Aurora::VERSION
    end

    it 'Valid version' do
      expect(subject.split('.').size).to eq(3)
      expect(subject.split('.')[0]).to eq(Mysql2::VERSION.split('.')[0])
      expect(subject.split('.')[1]).to eq(Mysql2::VERSION.split('.')[1])
      expect(subject.split('.')[2]).to match(/^\d+$/)
    end
  end

  describe 'Mysql2::Client' do
    subject do
      Mysql2::Client
    end

    it 'Return Mysql2::Aurora::Client' do
      expect(subject).to eq(Mysql2::Aurora::Client)
    end
  end

  describe '#client' do
    subject do
      client.client
    end

    it 'Return original Mysql2::Client instance' do
      expect(subject).to be_instance_of(Mysql2::Aurora::ORIGINAL_CLIENT_CLASS)
    end

    it 'Return correctly client' do
      expect(subject.query_options[:host]).to     eq(ENV['TEST_DB_HOST'])
      expect(subject.query_options[:username]).to eq(ENV['TEST_DB_USER'])
      expect(subject.query_options[:password]).to eq(ENV['TEST_DB_PASS'])
    end
  end

  describe '#query' do
    subject do
      client.query('SELECT CURRENT_USER() AS user')
    end

    it 'Return result' do
      expect(subject).to be_instance_of(Mysql2::Result)
      expect(subject.to_a.size).to eq(1)
      expect(subject.to_a.first['user']).to match(/^root@.+$/)
    end

    it 'Call original query' do
      expect(client.client).to receive(:query).once
      subject
    end

    context 'When raise Mysql2::Error' do
      before :each do
        allow_any_instance_of(Kernel).to receive(:warn)
        allow_any_instance_of(Kernel).to receive(:sleep)
        allow(client.client).to receive(:query).and_raise(Mysql2::Error, 'ERROR 1290 (HY000): The MySQL server is running with the --read-only option so it cannot execute this statement')
      end

      it 'Retry query' do
        expect(client).to receive(:reconnect!).exactly(2).times
        expect(client.client).to receive(:query).exactly(3).times
        expect { subject }.to raise_error(Mysql2::Error)
      end

      context 'Mysql2::Error is not failover error' do
        before :each do
          allow(client.client).to receive(:query).and_raise(Mysql2::Error, 'Unknown column \'hogehoge\' in \'field list\'')
        end

        it 'Not retry query' do
          expect(client).not_to receive(:reconnect!)
          expect(client.client).to receive(:query).once
          expect { subject }.to raise_error(Mysql2::Error)
        end
      end
    end

    context 'When StandardError' do
      before :each do
        allow(client.client).to receive(:query).and_raise(StandardError, 'hogehogehoge')
      end

      it 'Not retry query' do
        expect(client).not_to receive(:reconnect!)
        expect(client.client).to receive(:query).once
        expect { subject }.to raise_error(StandardError)
      end
    end
  end

  describe '#reconnect!' do
    subject do
      client.reconnect!
    end

    it 'Set new Mysql2::Client to #client' do
      expect { subject }.to change { client.client }
      expect(subject).to be_instance_of(Mysql2::Aurora::ORIGINAL_CLIENT_CLASS)
    end

    it 'Close old #client' do
      expect(client.client).to receive(:close).once
      subject
    end

    context 'When #close raise error' do
      before :each do
        allow(client.client).to receive(:close).and_raise(Mysql2::Error)
      end

      it 'Not raise error' do
        expect { subject }.not_to raise_error
      end

      it 'Set new Mysql2::Client to #client' do
        expect { subject }.to change { client.client }
      end
    end

    context 'When `client` is nil' do
      before :each do
        client.instance_variable_set(:@client, nil)
      end

      it 'Set new Mysql2::Client to #client' do
        expect { subject }.to change { client.client }.from(nil)
        expect(subject).to be_instance_of(Mysql2::Aurora::ORIGINAL_CLIENT_CLASS)
      end
    end
  end

  describe '#method_missing' do
    subject do
      client.ping
    end

    it 'Delegate to #client' do
      expect(client.client).to receive(:ping)
      subject
    end
  end

  describe '.method_missing' do
    subject do
      Mysql2::Aurora::Client.default_query_options
    end

    it 'Delegate to Mysql2::Client' do
      expect(Mysql2::Aurora::ORIGINAL_CLIENT_CLASS).to receive(:default_query_options)
      subject
    end
  end

  describe '.const_missing' do
    subject do
      Mysql2::Aurora::Client::CONNECT_ATTRS
    end

    it 'Delegate to Mysql2::Client' do
      expect(subject).to eq(Mysql2::Aurora::ORIGINAL_CLIENT_CLASS::CONNECT_ATTRS)
    end
  end
end
