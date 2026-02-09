<?php

namespace App\Controller\Api;

use App\Entity\Apartment;
use App\Repository\ApartmentRepository;
use Doctrine\ORM\EntityManagerInterface;
use Symfony\Bundle\FrameworkBundle\Controller\AbstractController;
use Symfony\Component\HttpFoundation\JsonResponse;
use Symfony\Component\HttpFoundation\Request;
use Symfony\Component\HttpFoundation\Response;
use Symfony\Component\Routing\Attribute\Route;
use Symfony\Component\Uid\Uuid;

#[Route('/api/apartments')]
class ApartmentController extends AbstractController
{
    #[Route('', name: 'api_apartments_list', methods: ['GET'])]
    public function list(ApartmentRepository $repo): JsonResponse
    {
        $items = $repo->findBy([], ['id' => 'DESC']);

        return $this->json(array_map([$this, 'serializeApartment'], $items));
    }

    #[Route('', name: 'api_apartments_create', methods: ['POST'])]
    public function create(Request $request, EntityManagerInterface $em): JsonResponse
    {
        $data = json_decode($request->getContent(), true);

        if (!is_array($data)) {
            return $this->json(['error' => 'Invalid JSON body'], Response::HTTP_BAD_REQUEST);
        }

        if (empty($data['title'])) {
            return $this->json(['error' => 'title is required'], Response::HTTP_BAD_REQUEST);
        }

        $apt = new Apartment();
        $apt->setTitle((string) $data['title']);
        $apt->setAddress($data['address'] ?? null);
        $apt->setSurface(isset($data['surface']) ? (int) $data['surface'] : null);
        $apt->setRooms(isset($data['rooms']) ? (int) $data['rooms'] : null);
        $apt->setPricePerNight(isset($data['pricePerNight']) ? (int) $data['pricePerNight'] : null);
        $apt->setDescription($data['description'] ?? null);
        $apt->setImageUrl($data['imageUrl'] ?? null);

        $em->persist($apt);
        $em->flush();

        return $this->json($this->serializeApartment($apt), Response::HTTP_CREATED);
    }

    #[Route('/{id}', name: 'api_apartments_get', methods: ['GET'])]
    public function getOne(string $id, ApartmentRepository $repo): JsonResponse
    {
        $apt = $this->findApartment($id, $repo);
        if (!$apt) {
            return $this->json(['error' => 'Not found'], Response::HTTP_NOT_FOUND);
        }

        return $this->json($this->serializeApartment($apt));
    }

    #[Route('/{id}', name: 'api_apartments_update', methods: ['PUT'])]
    public function update(string $id, Request $request, ApartmentRepository $repo, EntityManagerInterface $em): JsonResponse
    {
        $apt = $this->findApartment($id, $repo);
        if (!$apt) {
            return $this->json(['error' => 'Not found'], Response::HTTP_NOT_FOUND);
        }

        $data = json_decode($request->getContent(), true);
        if (!is_array($data)) {
            return $this->json(['error' => 'Invalid JSON body'], Response::HTTP_BAD_REQUEST);
        }

        if (array_key_exists('title', $data)) $apt->setTitle((string) $data['title']);
        if (array_key_exists('address', $data)) $apt->setAddress($data['address']);
        if (array_key_exists('surface', $data)) $apt->setSurface($data['surface'] !== null ? (int) $data['surface'] : null);
        if (array_key_exists('rooms', $data)) $apt->setRooms($data['rooms'] !== null ? (int) $data['rooms'] : null);
        if (array_key_exists('pricePerNight', $data)) $apt->setPricePerNight($data['pricePerNight'] !== null ? (int) $data['pricePerNight'] : null);
        if (array_key_exists('description', $data)) $apt->setDescription($data['description']);
        if (array_key_exists('imageUrl', $data)) $apt->setImageUrl($data['imageUrl']);

        $em->flush();

        return $this->json($this->serializeApartment($apt));
    }

    #[Route('/{id}', name: 'api_apartments_delete', methods: ['DELETE'])]
    public function delete(string $id, ApartmentRepository $repo, EntityManagerInterface $em): JsonResponse
    {
        $apt = $this->findApartment($id, $repo);
        if (!$apt) {
            return $this->json(['error' => 'Not found'], Response::HTTP_NOT_FOUND);
        }

        $em->remove($apt);
        $em->flush();

        return $this->json(['ok' => true]);
    }

    private function findApartment(string $id, ApartmentRepository $repo): ?Apartment
    {
        try {
            $uuid = Uuid::fromString($id);
        } catch (\Throwable) {
            return null;
        }

        return $repo->find($uuid);
    }

    private function serializeApartment(Apartment $apt): array
    {
        return [
            'id' => $apt->getId()?->toRfc4122(),
            'title' => $apt->getTitle(),
            'address' => $apt->getAddress(),
            'surface' => $apt->getSurface(),
            'rooms' => $apt->getRooms(),
            'pricePerNight' => $apt->getPricePerNight(),
            'description' => $apt->getDescription(),
            'imageUrl' => $apt->getImageUrl(),
        ];
    }
}
