module MultiMail
  module Receiver
    # Postmark's incoming email receiver.
    class Postmark
      include MultiMail::Receiver::Base

      # Transforms the content of Postmark's webhook into a list of messages.
      #
      # @param [Hash] params the content of Postmark's webhook
      # @return [Array<MultiMail::Message::Postmark>] messages
      def transform(params)
        headers = Multimap.new
        params['Headers'].each do |header|
          headers[header['Name']] = header['Value']
        end

        # Due to scoping issues, we can't call `transform_address` within `Mail.new`.
        from = transform_address(params['FromFull'])
        to   = params['ToFull'].map{|hash| transform_address(hash)}
        cc   = params['CcFull'].map{|hash| transform_address(hash)}

        message = Message::Postmark.new do
          headers    headers
          message_id params['MessageID']

          from      from
          to        to
          cc        cc
          reply_to  params['ReplyTo']
          subject   params['Subject']
          date      params['Date']

          text_part do
            body params['TextBody']
          end

          html_part do
            content_type 'text/html; charset=UTF-8'
            body CGI.unescapeHTML(params['HtmlBody'])
          end

          params['Attachments'].each do |attachment|
            add_file(:filename => attachment['Name'], :content => Base64.decode64(attachment['Content']))
          end
        end

        # Extra Postmark parameters.
        if params.key?('MailboxHash') && !params['MailboxHash'].empty?
          message.mailboxhash = params['MailboxHash']
        end
        if params.key?('MessageID') && !params['MessageID'].empty?
          message.messageid = params['MessageID']
        end
        if params.key?('Tag') && !params['Tag'].empty?
          message.tag = params['Tag']
        end

        [message]
      end

      # @param [Mail::Message] message a message
      # @return [Boolean] whether the message is spam
      # @see http://developer.postmarkapp.com/developer-inbound-parse.html#spam
      def spam?(message)
        message['X-Spam-Status'].value == 'Yes'
      end

    private

      def transform_address(hash)
        address = Mail::Address.new(hash['Email'])
        address.display_name = hash['Name']
        address.to_s
      end
    end
  end
end
