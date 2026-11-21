use jingle::Root;
use webrtc_sdp::parse_sdp;
use xep_0167::JingleRtpSessions;

mod jingle;
mod xep_0167;
mod xep_0176;
mod xep_0293;
mod xep_0294;
mod xep_0320;
mod xep_0338;
mod xep_0339;

pub fn sdp_str_to_jingle_str(sdp_str: &str, initiator: bool) -> Option<String> {
    let sdp_session = match parse_sdp(sdp_str, true) {
        Err(e) => {
            eprintln!("Could not parse sdpstring: {}", e);
            return None;
        }
        Ok(sdp) => sdp,
    };

    for warning in &sdp_session.warnings {
        eprintln!("mozilla sdp parser warning: {}", warning);
    }

    let jingle = match JingleRtpSessions::from_sdp(&sdp_session, initiator) {
        Err(e) => {
            eprintln!("Could not convert sdp to jingle: {}", e);
            return None;
        }
        Ok(jingle) => jingle,
    };

    match quick_xml::se::to_string(&jingle) {
        Err(e) => {
            eprintln!("Could not serialize jingle to xmlstring: {}", e);
            None
        }
        Ok(jingle_xml) => Some(jingle_xml),
    }
}

pub fn jingle_str_to_sdp_str(jingle_str: &str, initiator: bool) -> Option<String> {
    let jingle: Root = match quick_xml::de::from_str(jingle_str) {
        Err(e) => {
            eprintln!("Could not parse xmlstring: {}", e);
            return None;
        }
        Ok(j) => j,
    };

    let sdp = match JingleRtpSessions::to_sdp(&jingle, initiator) {
        Err(e) => {
            eprintln!("Could not convert jingle to sdp: {}", e);
            return None;
        }
        Ok(j) => j,
    };

    Some(
        sdp.to_string()
            .lines()
            .collect::<Vec<&str>>()
            .join("\r\n")
            .to_string()
            + "\r\n",
    )
}

pub(crate) fn is_none_or_default<T>(value: &Option<T>) -> bool
where
    T: Default + std::cmp::PartialEq,
{
    if let Some(inner_value) = value {
        return *inner_value == T::default();
    }
    true
}

#[cfg(test)]
mod tests {
    use super::*;

    // isaCloud: the session-initiate of isaCloud Web (call of 21/11/2026), whose "red" codec has a <parameter> without name.
    // (The app passes the children of <jingle/> inside a <root/>, see HelperTools xml2sdp.) It made the whole conversion fail ("Failed to convert jingle to raw sdp!") and the iOS app ended the call.
    const WEB_SESSION_INITIATE: &str = "<root><content creator='initiator' senders='both' name='0'><description media='audio' xmlns='urn:xmpp:jingle:apps:rtp:1'><payload-type name='opus' id='111' clockrate='48000' channels='2'><parameter name='minptime' value='10'/><parameter name='useinbandfec' value='1'/><rtcp-fb type='transport-cc' xmlns='urn:xmpp:jingle:apps:rtp:rtcp-fb:0'/></payload-type><payload-type name='red' id='63' clockrate='48000' channels='2'><parameter value='111/111'/></payload-type><payload-type id='9' clockrate='8000' name='G722'/><payload-type id='0' clockrate='8000' name='PCMU'/><rtp-hdrext id='1' uri='urn:ietf:params:rtp-hdrext:ssrc-audio-level' xmlns='urn:xmpp:jingle:apps:rtp:rtp-hdrext:0'/><source xmlns='urn:xmpp:jingle:apps:rtp:ssma:0' ssrc='482024179'><parameter name='cname' value='phbsc/OPDeAF6+KT'/></source><rtcp-mux/></description><transport xmlns='urn:xmpp:jingle:transports:ice-udp:1' pwd='fChGl6mQSgEX/MH18aSXFIUr' ufrag='7lsr'><fingerprint hash='sha-256' xmlns='urn:xmpp:jingle:apps:dtls:0' setup='actpass'>10:70:E6:FF:18:C0:94:3A:42:3B:63:4A:75:2D:95:26:08:9C:15:68:C4:C9:03:57:98:DF:D1:B5:B7:AC:EE:E9</fingerprint></transport></content><group xmlns='urn:xmpp:jingle:apps:grouping:0' semantics='BUNDLE'><content name='0'/></group></root>";

    #[test]
    fn parameter_without_name_is_converted_to_a_bare_fmtp_token() {
        let sdp = jingle_str_to_sdp_str(WEB_SESSION_INITIATE, false)
            .expect("jingle with a nameless <parameter> must convert");
        assert!(
            sdp.lines().any(|l| l.starts_with("a=fmtp:63 ") && l.ends_with("111/111")),
            "sdp was: {}",
            sdp
        );
        // the named parameters keep working
        assert!(sdp.contains("a=fmtp:111 "), "sdp was: {}", sdp);
        assert!(sdp.contains("useinbandfec=1"), "sdp was: {}", sdp);
    }
}
