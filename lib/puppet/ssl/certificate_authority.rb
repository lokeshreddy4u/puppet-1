require 'puppet/ssl/host'
require 'puppet/ssl/certificate_request'

# The class that knows how to sign certificates.  It creates
# a 'special' SSL::Host whose name is 'ca', thus indicating
# that, well, it's the CA.  There's some magic in the
# indirector/ssl_file terminus base class that does that
# for us.
#   This class mostly just signs certs for us, but
# it can also be seen as a general interface into all of the
# SSL stuff.
class Puppet::SSL::CertificateAuthority
    require 'puppet/ssl/certificate_factory'

    attr_reader :name, :host

    # Generate our CA certificate.
    def generate_ca_certificate
        generate_password unless password?

        # Create a new cert request.  We do this
        # specially, because we don't want to actually
        # save the request anywhere.
        request = Puppet::SSL::CertificateRequest.new(host.name)
        request.generate(host.key)

        # Create a self-signed certificate.
        @certificate = sign(name, :ca, request)
    end

    def initialize
        Puppet.settings.use :main, :ssl, :ca

        @name = Puppet[:certname]

        @host = Puppet::SSL::Host.new(Puppet::SSL::Host.ca_name)
        @host.password_file = Puppet[:capass]
    end

    # Sign a given certificate request.
    def sign(host, cert_type = :server, self_signing_csr = nil)

        # This is a self-signed certificate
        if self_signing_csr
            csr = self_signing_csr
            issuer = csr.content
        else
            raise ArgumentError, "Cannot find CA certificate; cannot sign certificate for %s" % host unless certificate
            unless csr = Puppet::SSL::CertificateRequest.find(host, :in => :ca_file)
                raise ArgumentError, "Could not find certificate request for %s" % host
            end
            issuer = certificate
        end

        cert = Puppet::SSL::Certificate.new(host)
        cert.content = Puppet::SSL::CertificateFactory.new(cert_type, csr.content, issuer, next_serial).result
        cert.content.sign(key, OpenSSL::Digest::SHA1.new)

        Puppet.notice "Signed certificate request for %s" % host

        # Save the now-signed cert.  This should get routed correctly depending
        # on the certificate type.
        cert.save

        return cert
    end

    # Generate a new password for the CA.
    def generate_password
        pass = ""
        20.times { pass += (rand(74) + 48).chr }

        begin
            Puppet.settings.write(:capass) { |f| f.print pass }
        rescue Errno::EACCES => detail
            raise Puppet::Error, "Could not write CA password: %s" % detail.to_s
        end

        @password = pass

        return pass
    end

    # Read the next serial from the serial file, and increment the
    # file so this one is considered used.
    def next_serial
        serial = nil
        Puppet.settings.readwritelock(:serial) { |f|
            if FileTest.exist?(Puppet[:serial])
                serial = File.read(Puppet.settings[:serial]).chomp.hex
            else
                serial = 0x0
            end

            # We store the next valid serial, not the one we just used.
            f << "%04X" % (serial + 1)
        }

        return serial
    end

    # Does the password file exist?
    def password?
        FileTest.exist? Puppet[:capass]
    end
end