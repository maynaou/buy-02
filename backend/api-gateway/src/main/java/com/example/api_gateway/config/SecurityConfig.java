package com.example.api_gateway.config;

import java.util.Arrays;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.config.annotation.web.reactive.EnableWebFluxSecurity;
import org.springframework.security.config.web.server.ServerHttpSecurity;
import org.springframework.security.oauth2.jwt.NimbusReactiveJwtDecoder;
import org.springframework.security.oauth2.jwt.ReactiveJwtDecoder;
import org.springframework.security.web.server.SecurityWebFilterChain;
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.cors.reactive.CorsConfigurationSource;
import org.springframework.web.cors.reactive.UrlBasedCorsConfigurationSource;
import org.springframework.security.web.server.ServerAuthenticationEntryPoint;
import reactor.core.publisher.Mono;

import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;



@Configuration
@EnableWebFluxSecurity
public class SecurityConfig {

    RsaKeysConfig rsaKeysConfig;

    private final String allowedOrigins;

    public SecurityConfig(
            RsaKeysConfig rsaKeysConfig,
            @Value("${app.cors.allowed.origins:https://localhost:4200}") String allowedOrigins) {
        this.rsaKeysConfig = rsaKeysConfig;
        this.allowedOrigins = allowedOrigins;
    }
      
    @Bean
    public SecurityWebFilterChain securityWebFilterChain(ServerHttpSecurity http) {
        return http
              .cors(cors -> cors.configurationSource(corsConfigurationSource()))
              .csrf(csrf-> csrf.disable())
              .authorizeExchange(authorize -> authorize.pathMatchers("/actuator/health/**").permitAll()
                                                       .pathMatchers("/api/auth/**").permitAll()
                                                       .pathMatchers(HttpMethod.GET, "/api/products/**").permitAll()
              )
              .authorizeExchange(authorize -> authorize.anyExchange().authenticated())
              .oauth2ResourceServer(oauth2 -> oauth2.jwt(jwt-> jwt.jwtDecoder(jwtDecoder()))
                                                    .authenticationEntryPoint(customAuthenticationEntryPoint()))
              .build();
    }

    @Bean
    ReactiveJwtDecoder jwtDecoder() {
        return NimbusReactiveJwtDecoder.withPublicKey(rsaKeysConfig.publicKey()).build();
    }

    @Bean
    public ServerAuthenticationEntryPoint customAuthenticationEntryPoint() {
        return (exchange, ex) -> {
            var response = exchange.getResponse();
            response.setStatusCode(HttpStatus.UNAUTHORIZED);
            response.getHeaders().setContentType(MediaType.APPLICATION_JSON);
            
            String body = String.format(
                "{\"status\": 401, \"error\": \"Unauthorized\", \"message\": \"%s\", \"path\": \"%s\"}",
                "Token JWT invalide ou expiré",
                exchange.getRequest().getPath().value()
            );
            
            var buffer = response.bufferFactory().wrap(body.getBytes());
            return response.writeWith(Mono.just(buffer));
        };
    }


    @Bean
    public CorsConfigurationSource corsConfigurationSource() {
        CorsConfiguration configuration = new CorsConfiguration();
        configuration.setAllowedOrigins(Arrays.stream(allowedOrigins.split(","))
                .map(String::trim)
                .filter(origin -> !origin.isEmpty())
                .toList());
        configuration.setAllowedMethods(Arrays.asList("GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"));
        configuration.setAllowedHeaders(Arrays.asList("*"));
        configuration.setAllowCredentials(true);
        configuration.setMaxAge(3600L);
        
        UrlBasedCorsConfigurationSource source = new UrlBasedCorsConfigurationSource();
        source.registerCorsConfiguration("/**", configuration);
        return source;
    }

}
