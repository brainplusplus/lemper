# Set the default backend (Nginx)
backend default {
	# My Nginx server listen on IP address 127.0.0.1 and TCP port 8080
	.host = "127.0.0.1";
	.port = "8080";
	# Increase guru timeout
	# http://vincentfretin.ecreall.com/articles/varnish-guru-meditation-on-timeout
	.first_byte_timeout = 300s;
}

# Purge ACL
acl purge {
	# Only localhost can purge my cache
	"127.0.0.1";
	"localhost";
}

# This function is used when a request is send by a HTTP client (Browser) 
sub vcl_recv {
	set req.backend = default; 

	# Compatibility with Apache format log
	if (req.restarts == 0) {
 		if (req.http.x-forwarded-for) {
 	    		set req.http.X-Forwarded-For = req.http.X-Forwarded-For + ", " + client.ip;
	 	} else {
			set req.http.X-Forwarded-For = client.ip;
	 	}
     }

	# Normalize the header, remove the port (in case you're testing this on various TCP ports)
	set req.http.Host = regsub(req.http.Host, ":[0-9]+", "");

	# Allow purging from ACL
	if (req.request == "PURGE") {
		# If not allowed then a error 405 is returned
		if (!client.ip ~ purge) {
			error 405 "This IP is not allowed to send PURGE requests.";
		}	
		# If allowed, do a cache_lookup -> vlc_hit() or vlc_miss()
		return (lookup);
	}

	# Post requests will not be cached
	if (req.request == "POST") {
		return (pass);
	}

	# --- Wordpress specific configuration
	
	# Did not cache the admin and login pages
	if ( !( req.url ~ "/wp-(login|admin)") ) {
	  unset req.http.Cookie;
	}
	# Normalize Accept-Encoding header and compression
	# https://www.varnish-cache.org/docs/3.0/tutorial/vary.html
	if (req.http.Accept-Encoding) {
		# Do no compress compressed files...
		if (req.url ~ "\.(jpg|png|gif|gz|tgz|bz2|tbz|mp3|ogg)$") {
			   	remove req.http.Accept-Encoding;
		} elsif (req.http.Accept-Encoding ~ "gzip") {
		    	set req.http.Accept-Encoding = "gzip";
		} elsif (req.http.Accept-Encoding ~ "deflate") {
		    	set req.http.Accept-Encoding = "deflate";
		} else {
			remove req.http.Accept-Encoding;
		}
	}

	
	# --- End of Wordpress specific configuration
	
	# Cache all others requests
	return (lookup);
}
 
sub vcl_pipe {
	return (pipe);
}
 
sub vcl_pass {
	return (pass);
}
 
# The data on which the hashing will take place
sub vcl_hash {
 	hash_data(req.url);
 	if (req.http.host) {
     	hash_data(req.http.host);
 	} else {
     	hash_data(server.ip);
 	}

	# If the client supports compression, keep that in a different cache
    	if (req.http.Accept-Encoding) {
        	hash_data(req.http.Accept-Encoding);
	}
     
	return (hash);
}
 
sub vcl_hit {
	# Allow purges
	if (req.request == "PURGE") {
		purge;
		error 200 "Purged.";
	}

	return (deliver);
}
 
sub vcl_miss {
	# Allow purges
	if (req.request == "PURGE") {
		purge;
		error 200 "Purged.";
	}
        
	return (fetch);
}

# This function is used when a request is sent by our backend (Nginx server)
sub vcl_fetch {
	# For static content related to the theme, strip all backend cookies
	if (req.url ~ "\.(css|js|png|gif|jp(e?)g)") {
		unset beresp.http.cookie;
	}

	# A TTL of 30 minutes
	set beresp.ttl = 1800s;
	
	return (deliver);
}
 
# The routine when we deliver the HTTP request to the user
# Last chance to modify headers that are sent to the client
sub vcl_deliver {
	if (obj.hits > 0) { 
		set resp.http.X-Cache = "cached";
	} else {
		set resp.http.x-Cache = "uncached";
	}

	# Remove some headers: PHP version
	unset resp.http.X-Powered-By;

	# Remove some headers: Apache version & OS
	unset resp.http.Server;

	return (deliver);
}
 
sub vcl_init {
 	return (ok);
}
 
sub vcl_fini {
 	return (ok);
}