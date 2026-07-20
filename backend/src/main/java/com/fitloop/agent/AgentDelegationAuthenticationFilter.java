package com.fitloop.agent;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.util.List;
import org.springframework.boot.autoconfigure.condition.ConditionalOnBean;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

@Component
@ConditionalOnBean(AgentDelegationTokenService.class)
public class AgentDelegationAuthenticationFilter extends OncePerRequestFilter {
    private final AgentDelegationTokenService tokens;

    public AgentDelegationAuthenticationFilter(AgentDelegationTokenService tokens) { this.tokens = tokens; }

    @Override
    protected boolean shouldNotFilter(HttpServletRequest request) {
        return !request.getRequestURI().startsWith("/internal/v1/agent")
                || request.getRequestURI().endsWith("/delegation-token");
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain)
            throws ServletException, IOException {
        String header = request.getHeader("Authorization");
        if (header != null && header.startsWith("Bearer ")) {
            try {
                AgentDtos.ToolContext context = tokens.verify(header.substring(7));
                var authentication = new UsernamePasswordAuthenticationToken("agent:" + context.runId(), null,
                        List.of(new SimpleGrantedAuthority("SCOPE_agent.internal")));
                authentication.setDetails(context);
                SecurityContextHolder.getContext().setAuthentication(authentication);
            } catch (IllegalArgumentException ignored) {
                SecurityContextHolder.clearContext();
            }
        }
        chain.doFilter(request, response);
    }
}
