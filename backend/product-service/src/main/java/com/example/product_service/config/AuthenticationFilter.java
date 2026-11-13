package com.example.product_service.config;

import java.io.IOException;
import java.util.List;

import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

@Component
@SuppressWarnings("null")
public class AuthenticationFilter  extends OncePerRequestFilter {
     
    @Override
    protected void doFilterInternal(HttpServletRequest req, HttpServletResponse res, FilterChain chain) throws ServletException, IOException {
        String userId = req.getHeader("X-User-Idd");
        String role = req.getHeader("X-User-Role");

        if (userId != null && role != null) {
            SecurityContextHolder.getContext().setAuthentication(
                new UsernamePasswordAuthenticationToken(userId, null,
                    List.of(new SimpleGrantedAuthority(role))));
        }
        chain.doFilter(req, res);
    }
}

