<?php

namespace App\Command;

use App\Entity\User;
use Doctrine\ORM\EntityManagerInterface;
use Symfony\Component\Console\Attribute\AsCommand;
use Symfony\Component\Console\Command\Command;
use Symfony\Component\Console\Input\InputArgument;
use Symfony\Component\Console\Input\InputInterface;
use Symfony\Component\Console\Output\OutputInterface;
use Symfony\Component\Console\Style\SymfonyStyle;
use Symfony\Component\PasswordHasher\Hasher\UserPasswordHasherInterface;

#[AsCommand(
    name: 'app:user:create',
    description: 'Create a user (optionally admin) for the API.',
)]
class CreateUserCommand extends Command
{
    public function __construct(
        private readonly EntityManagerInterface $em,
        private readonly UserPasswordHasherInterface $hasher,
    ) {
        parent::__construct();
    }

    protected function configure(): void
    {
        $this
            ->addArgument('email', InputArgument::REQUIRED, 'User email (unique)')
            ->addArgument('password', InputArgument::REQUIRED, 'User password (plain)')
            ->addArgument('admin', InputArgument::OPTIONAL, 'Set to "admin" to grant ROLE_ADMIN', 'user');
    }

    protected function execute(InputInterface $input, OutputInterface $output): int
    {
        $io = new SymfonyStyle($input, $output);

        $email = strtolower(trim((string) $input->getArgument('email')));
        $plainPassword = (string) $input->getArgument('password');
        $adminFlag = strtolower((string) $input->getArgument('admin'));

        if (!filter_var($email, FILTER_VALIDATE_EMAIL)) {
            $io->error('Invalid email.');
            return Command::FAILURE;
        }

        if (strlen($plainPassword) < 8) {
            $io->error('Password must be at least 8 characters.');
            return Command::FAILURE;
        }

        $existing = $this->em->getRepository(User::class)->findOneBy(['email' => $email]);
        if ($existing) {
            $io->error('User already exists.');
            return Command::FAILURE;
        }

        $user = new User();
        $user->setEmail($email);

        $roles = ['ROLE_USER'];
        if (in_array($adminFlag, ['admin', 'yes', 'true', '1'], true)) {
            $roles[] = 'ROLE_ADMIN';
        }
        $user->setRoles(array_values(array_unique($roles)));

        $user->setPassword($this->hasher->hashPassword($user, $plainPassword));

        $this->em->persist($user);
        $this->em->flush();

        $io->success(sprintf(
            'User created: %s (%s)',
            $user->getEmail(),
            implode(', ', $user->getRoles())
        ));

        return Command::SUCCESS;
    }
}
