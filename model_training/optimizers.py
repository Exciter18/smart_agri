import numpy as np

class BinaryPSO:
    def __init__(self, num_particles, num_features, max_iter, fitness_func):
        self.num_particles = num_particles
        self.num_features = num_features
        self.max_iter = max_iter
        self.fitness_func = fitness_func
        
    def optimize(self):
        positions = np.random.randint(2, size=(self.num_particles, self.num_features))
        velocities = np.zeros((self.num_particles, self.num_features))
        
        pbest_positions = positions.copy()
        pbest_fitness = np.array([self.fitness_func(p) for p in positions])
        
        gbest_idx = np.argmin(pbest_fitness)
        gbest_position = pbest_positions[gbest_idx].copy()
        gbest_fitness = pbest_fitness[gbest_idx]
        
        convergence_curve = []
        w, c1, c2 = 0.9, 2.0, 2.0
        
        for t in range(self.max_iter):
            r1 = np.random.rand(self.num_particles, self.num_features)
            r2 = np.random.rand(self.num_particles, self.num_features)
            
            velocities = (w * velocities + 
                          c1 * r1 * (pbest_positions - positions) + 
                          c2 * r2 * (gbest_position - positions))
            
            # Chuyen doi van toc sang nhi phan qua ham Sigmoid
            sigmoid_v = 1 / (1 + np.exp(-velocities))
            rand_vals = np.random.rand(self.num_particles, self.num_features)
            positions = (sigmoid_v > rand_vals).astype(int)
            
            for i in range(self.num_particles):
                if np.sum(positions[i]) == 0:
                    positions[i][np.random.randint(self.num_features)] = 1
                    
                fit = self.fitness_func(positions[i])
                if fit < pbest_fitness[i]:
                    pbest_fitness[i] = fit
                    pbest_positions[i] = positions[i].copy()
                    
                if fit < gbest_fitness:
                    gbest_fitness = fit
                    gbest_position = positions[i].copy()
            
            w = 0.9 - t * (0.5 / self.max_iter)
            convergence_curve.append(gbest_fitness)
            print(f"PSO Iteration {t+1}/{self.max_iter}, Best Fitness: {gbest_fitness:.4f}")
            
        return gbest_position, convergence_curve


class BinaryGA:
    def __init__(self, pop_size, num_features, max_iter, fitness_func):
        self.pop_size = pop_size
        self.num_features = num_features
        self.max_iter = max_iter
        self.fitness_func = fitness_func
        self.mutation_rate = 0.05
        
    def optimize(self):
        population = np.random.randint(2, size=(self.pop_size, self.num_features))
        convergence_curve = []
        
        gbest_position = None
        gbest_fitness = float('inf')
        
        for t in range(self.max_iter):
            fitness_scores = np.array([self.fitness_func(ind) for ind in population])
            
            best_idx = np.argmin(fitness_scores)
            if fitness_scores[best_idx] < gbest_fitness:
                gbest_fitness = fitness_scores[best_idx]
                gbest_position = population[best_idx].copy()
                
            convergence_curve.append(gbest_fitness)
            print(f"GA Iteration {t+1}/{self.max_iter}, Best Fitness: {gbest_fitness:.4f}")
            
            new_population = np.zeros((self.pop_size, self.num_features), dtype=int)
            for i in range(0, self.pop_size, 2):
                idx1 = np.random.choice(self.pop_size, 2, replace=False)
                parent1 = population[idx1[np.argmin(fitness_scores[idx1])]]
                
                idx2 = np.random.choice(self.pop_size, 2, replace=False)
                parent2 = population[idx2[np.argmin(fitness_scores[idx2])]]
                
                crossover_pt = np.random.randint(1, self.num_features-1)
                child1 = np.concatenate((parent1[:crossover_pt], parent2[crossover_pt:]))
                child2 = np.concatenate((parent2[:crossover_pt], parent1[crossover_pt:]))
                
                new_population[i] = child1
                if i + 1 < self.pop_size:
                    new_population[i+1] = child2
                    
            mutation_mask = np.random.rand(self.pop_size, self.num_features) < self.mutation_rate
            new_population = np.where(mutation_mask, 1 - new_population, new_population)
            
            for i in range(self.pop_size):
                if np.sum(new_population[i]) == 0:
                    new_population[i][np.random.randint(self.num_features)] = 1
                    
            population = new_population
            
        return gbest_position, convergence_curve


class BinaryGWO:
    def __init__(self, num_wolves, num_features, max_iter, fitness_func):
        self.num_wolves = num_wolves
        self.num_features = num_features
        self.max_iter = max_iter
        self.fitness_func = fitness_func
        
    def optimize(self):
        positions = np.random.randint(2, size=(self.num_wolves, self.num_features))
        
        alpha_pos = np.zeros(self.num_features)
        beta_pos = np.zeros(self.num_features)
        delta_pos = np.zeros(self.num_features)
        
        alpha_fit = float('inf')
        beta_fit = float('inf')
        delta_fit = float('inf')
        
        convergence_curve = []
        
        for t in range(self.max_iter):
            for i in range(self.num_wolves):
                if np.sum(positions[i]) == 0:
                    positions[i][np.random.randint(self.num_features)] = 1
                    
                fit = self.fitness_func(positions[i])
                
                if fit < alpha_fit:
                    delta_fit, delta_pos = beta_fit, beta_pos.copy()
                    beta_fit, beta_pos = alpha_fit, alpha_pos.copy()
                    alpha_fit, alpha_pos = fit, positions[i].copy()
                elif fit < beta_fit:
                    delta_fit, delta_pos = beta_fit, beta_pos.copy()
                    beta_fit, beta_pos = fit, positions[i].copy()
                elif fit < delta_fit:
                    delta_fit, delta_pos = fit, positions[i].copy()
            
            a = 2 - t * (2 / self.max_iter)
            
            for i in range(self.num_wolves):
                for j in range(self.num_features):
                    r1, r2 = np.random.rand(), np.random.rand()
                    A1, C1 = 2 * a * r1 - a, 2 * r2
                    D_alpha = abs(C1 * alpha_pos[j] - positions[i, j])
                    X1 = alpha_pos[j] - A1 * D_alpha
                    
                    r1, r2 = np.random.rand(), np.random.rand()
                    A2, C2 = 2 * a * r1 - a, 2 * r2
                    D_beta = abs(C2 * beta_pos[j] - positions[i, j])
                    X2 = beta_pos[j] - A2 * D_beta
                    
                    r1, r2 = np.random.rand(), np.random.rand()
                    A3, C3 = 2 * a * r1 - a, 2 * r2
                    D_delta = abs(C3 * delta_pos[j] - positions[i, j])
                    X3 = delta_pos[j] - A3 * D_delta
                    
                    X_new = (X1 + X2 + X3) / 3
                    
                    sigmoid_val = 1 / (1 + np.exp(-10 * (X_new - 0.5)))
                    positions[i, j] = 1 if sigmoid_val > np.random.rand() else 0
                    
            convergence_curve.append(alpha_fit)
            print(f"GWO Iteration {t+1}/{self.max_iter}, Best Fitness: {alpha_fit:.4f}")
            
        return alpha_pos, convergence_curve


class BinaryWOA:
    def __init__(self, num_whales, num_features, max_iter, fitness_func):
        self.num_whales = num_whales
        self.num_features = num_features
        self.max_iter = max_iter
        self.fitness_func = fitness_func
        
    def optimize(self):
        positions = np.random.randint(2, size=(self.num_whales, self.num_features))
        leader_pos = np.zeros(self.num_features)
        leader_score = float('inf')
        convergence_curve = []
        
        for t in range(self.max_iter):
            for i in range(self.num_whales):
                if np.sum(positions[i]) == 0:
                    positions[i][np.random.randint(self.num_features)] = 1
                    
                fit = self.fitness_func(positions[i])
                
                if fit < leader_score:
                    leader_score = fit
                    leader_pos = positions[i].copy()
                    
            a = 2 - t * (2 / self.max_iter)
            
            for i in range(self.num_whales):
                p = np.random.rand()
                for j in range(self.num_features):
                    r1 = np.random.rand()
                    r2 = np.random.rand()
                    A = 2 * a * r1 - a
                    C = 2 * r2
                    l = (np.random.rand() - 0.5) * 2
                    
                    if p < 0.5:
                        if abs(A) >= 1:
                            rand_leader_idx = np.random.randint(0, self.num_whales)
                            X_rand = positions[rand_leader_idx, j]
                            D_X_rand = abs(C * X_rand - positions[i, j])
                            X_new = X_rand - A * D_X_rand
                        else:
                            D_Leader = abs(C * leader_pos[j] - positions[i, j])
                            X_new = leader_pos[j] - A * D_Leader
                    else:
                        distance2Leader = abs(leader_pos[j] - positions[i, j])
                        X_new = distance2Leader * np.exp(l) * np.cos(l * 2 * np.pi) + leader_pos[j]
                        
                    sigmoid_val = 1 / (1 + np.exp(-10 * (X_new - 0.5)))
                    positions[i, j] = 1 if sigmoid_val > np.random.rand() else 0
                    
            convergence_curve.append(leader_score)
            print(f"WOA Iteration {t+1}/{self.max_iter}, Best Fitness: {leader_score:.4f}")
            
        return leader_pos, convergence_curve


class BinarySCA:
    def __init__(self, num_agents, num_features, max_iter, fitness_func):
        self.num_agents = num_agents
        self.num_features = num_features
        self.max_iter = max_iter
        self.fitness_func = fitness_func
        
    def optimize(self):
        positions = np.random.randint(2, size=(self.num_agents, self.num_features))
        dest_pos = np.zeros(self.num_features)
        dest_score = float('inf')
        convergence_curve = []
        
        for t in range(self.max_iter):
            for i in range(self.num_agents):
                if np.sum(positions[i]) == 0:
                    positions[i][np.random.randint(self.num_features)] = 1
                    
                fit = self.fitness_func(positions[i])
                
                if fit < dest_score:
                    dest_score = fit
                    dest_pos = positions[i].copy()
                    
            r1 = 2.0 - t * (2.0 / self.max_iter)
            
            for i in range(self.num_agents):
                for j in range(self.num_features):
                    r2 = 2 * np.pi * np.random.rand()
                    r3 = 2 * np.random.rand()
                    r4 = np.random.rand()
                    
                    if r4 < 0.5:
                        X_new = positions[i, j] + r1 * np.sin(r2) * abs(r3 * dest_pos[j] - positions[i, j])
                    else:
                        X_new = positions[i, j] + r1 * np.cos(r2) * abs(r3 * dest_pos[j] - positions[i, j])
                        
                    sigmoid_val = 1 / (1 + np.exp(-10 * (X_new - 0.5)))
                    positions[i, j] = 1 if sigmoid_val > np.random.rand() else 0
                    
            convergence_curve.append(dest_score)
            print(f"SCA Iteration {t+1}/{self.max_iter}, Best Fitness: {dest_score:.4f}")
            
        return dest_pos, convergence_curve