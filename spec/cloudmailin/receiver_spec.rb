require File.expand_path(File.dirname(__FILE__) + '/../spec_helper')
require 'multi_mail/cloudmailin/receiver'

describe MultiMail::Receiver::Cloudmailin do
  context 'with invalid HTTP POST format' do
    let :service do
      MultiMail::Receiver.new({
        :provider => :cloudmailin,
        :http_post_format => 'invalid',
      })
    end

    describe '#transform' do
      it 'should raise an error if :http_post_format is invalid' do
        expect{ service.transform({}) }.to raise_error(ArgumentError)
      end
    end
  end

  [false, true].each do |action_dispatch|
    let :action_dispatch do
      action_dispatch
    end

    ['raw', 'json', 'multipart', '', nil].each do |http_post_format|
      context "with #{http_post_format.inspect} format and #{action_dispatch ? 'ActionDispatch' : 'Rack'}" do
        let :actual_http_post_format do
          http_post_format.to_s.empty? ? 'raw' : http_post_format
        end

        let :service do
          MultiMail::Receiver.new({
            :provider => :cloudmailin,
            :http_post_format => http_post_format,
          })
        end

        def params(fixture)
          MultiMail::Receiver::Cloudmailin.parse(response("cloudmailin/#{actual_http_post_format}", fixture, action_dispatch))
        end

        describe '#transform' do
          it 'should return a mail message' do
            helper(service.transform(params('valid')))
          end

          it 'should return a mail message with URL attachments' do
            helper(MultiMail::Receiver.new({
              :provider => :cloudmailin,
              :http_post_format => http_post_format,
              :attachment_store => true,
            }).transform(params('attachment_store')), true)
          end

          def helper(messages, attachment_store = false)
            messages.size.should == 1
            message = messages[0]

            # Headers
            message.date.should    == DateTime.parse('Mon, 15 Apr 2013 20:20:12 -04:00')
            message.from.should    == ['james@opennorth.ca']
            message.to.should      == ['5dae6f85cd65d30d384a@cloudmailin.net']
            message.subject.should == 'Test'

            # Body
            message.multipart?.should == true
            message.parts.size.should == 4
            text_part = message.parts.find{|part| part.content_type == 'text/plain'}
            html_part = message.parts.find{|part| part.content_type == 'text/html; charset=UTF-8'}
            text_part.body.decoded.should == "bold text\n\n\n\nsome more bold text\n\n\n\nsome italic text\n\n> multiline\n> quoted\n> text\n\n\n--\nSignature block"

            # @note Due to a Cloudmailin bug, the HTML part is missing content
            #   unless you use the "raw" HTTP POST format or URL attachments.
            if actual_http_post_format == 'raw' || attachment_store
              html_part.body.decoded.should == %(<html><head></head><body style="word-wrap: break-word; -webkit-nbsp-mode: space; -webkit-line-break: after-white-space; "><b>bold text</b><div><br></div><div></div></body></html><html><body style="word-wrap: break-word; -webkit-nbsp-mode: space; -webkit-line-break: after-white-space; "><head></head><br><div></div><div><br></div><div><b>some more bold text</b></div><div><b><br></b></div><div><b></b></div></body></html><html><head></head><body style="word-wrap: break-word; -webkit-nbsp-mode: space; -webkit-line-break: after-white-space; "><br><div><b></b></div><div><b><span class="Apple-style-span" style="font-weight: normal; "><br></span></b></div><div><b><span class="Apple-style-span" style="font-weight: normal; "><i>some italic text</i></span></b></div><div><b><span class="Apple-style-span" style="font-weight: normal; "><br></span></b></div><div><blockquote type="cite">multiline</blockquote><blockquote type="cite">quoted</blockquote><blockquote type="cite">text</blockquote></div><div><br></div><div>--</div><div>Signature block</div></body></html>)
            else
              html_part.body.decoded.should == %(<html><head></head><body style="word-wrap: break-word; -webkit-nbsp-mode: space; -webkit-line-break: after-white-space; "><b>bold text</b><div><br></div><div></div></body></html>)
            end

            # Attachments
            attachment0 = message.attachments.find{|attachment| attachment.filename == 'foo.txt'}
            attachment1 = message.attachments.find{|attachment| attachment.filename == 'bar.txt'}
            # @note Cloudmailin removes the newline at the end of the file,
            #   unless you use the "raw" HTTP POST format or URL attachments.
            if actual_http_post_format == 'raw' || attachment_store
              attachment0.read.should == "Lorem ipsum dolor sit amet, consectetur adipiscing elit.\n"
              attachment1.read.should == "Nam accumsan euismod eros et rhoncus.\n"
            else
              attachment0.read.should == "Lorem ipsum dolor sit amet, consectetur adipiscing elit."
              attachment1.read.should == "Nam accumsan euismod eros et rhoncus."
            end

            # Extra Cloudmailin parameters
            if actual_http_post_format == 'raw'
              message.reply_plain.should be_nil
            else
              message.reply_plain.should == "bold text\n\n\n\nsome more bold text\n\n\n\nsome italic text\n"
            end
            message.spf_result.should == 'pass'
          end
        end

        describe '#spam?' do
          it 'should return true if the response is spam' do
            message = service.transform(params('spam'))[0]
            service.spam?(message).should == true
          end

          it 'should return false if the response is ham' do
            message = service.transform(params('valid'))[0]
            service.spam?(message).should == false
          end
        end
      end
    end
  end
end
